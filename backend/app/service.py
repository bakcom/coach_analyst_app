"""High-level scouting service: catalog, per-club datasets, the pooled player
list and analytics.

Pool builds run on a durable RQ/Redis queue when available (surviving restarts);
otherwise they fall back to an in-process background task.
"""

from __future__ import annotations

import asyncio
import datetime as dt
import json
import os

from . import analysis
from .builder import build_pool_profiles, ensure_competition_profiles
from .config import CACHE_DIR, MAX_MATCHES_PER_COMPETITION, POPULAR_LEAGUES
from .jobs import build_pool_job, warm_competitions_job
from .statsbomb import StatsBombClient
from .storage import write_json_atomic
from .taskqueue import pool_queue, redis_available

POOL_FILE = CACHE_DIR / "pool.json"

_STATUS_MAP = {
    "queued": "queued",
    "started": "running",
    "finished": "ready",
    "failed": "failed",
    "deferred": "queued",
    "scheduled": "queued",
}


def _short_name(name: str) -> str:
    letters = [c for c in name.upper() if c.isalnum()]
    return "".join(letters[:3])


def _team(tid: int, name: str) -> dict:
    return {"id": f"sb-{tid}", "name": name, "shortName": _short_name(name), "crestSymbol": "shield.fill"}


class ScoutingService:
    def __init__(self, client: StatsBombClient, max_matches: int = MAX_MATCHES_PER_COMPETITION) -> None:
        self.client = client
        self.max_matches = max_matches
        self._pool: list[dict] = []
        self._pool_mtime: float = -1.0
        self._job: dict = {"jobId": "inline", "status": "idle", "progress": 0.0, "message": "", "playerCount": 0}
        self._job_task: asyncio.Task | None = None

    # MARK: - Pool storage

    def current_pool(self) -> list[dict]:
        try:
            mtime = os.path.getmtime(POOL_FILE)
        except OSError:
            return self._pool
        if mtime != self._pool_mtime:
            try:
                self._pool = json.loads(POOL_FILE.read_text())
                self._pool_mtime = mtime
            except (OSError, json.JSONDecodeError):
                pass
        return self._pool

    def _pool_count(self) -> int:
        return len(self.current_pool())

    # MARK: - Catalog

    async def competitions(self) -> list[dict]:
        raw = await self.client.competitions()
        comps = [
            {
                "competitionID": c["competition_id"],
                "seasonID": c["season_id"],
                "name": c["competition_name"],
                "country": c["country_name"],
                "gender": c["competition_gender"],
                "seasonName": c["season_name"],
            }
            for c in raw
        ]
        comps.sort(key=lambda c: (c["country"], c["name"], c["seasonName"]))
        return comps

    async def fixtures(self, competition_id: int, season_id: int) -> list[dict]:
        raw = await self.client.matches(competition_id, season_id)
        fixtures = []
        for m in raw:
            date = dt.date.fromisoformat(m["match_date"])
            fixtures.append({
                "id": m["match_id"],
                "date": dt.datetime(date.year, date.month, date.day, tzinfo=dt.timezone.utc).isoformat(),
                "home": _team(m["home_team"]["home_team_id"], m["home_team"]["home_team_name"]),
                "away": _team(m["away_team"]["away_team_id"], m["away_team"]["away_team_name"]),
                "homeScore": m["home_score"],
                "awayScore": m["away_score"],
            })
        fixtures.sort(key=lambda f: f["date"], reverse=True)
        return fixtures

    async def teams(self, competition_id: int, season_id: int) -> list[dict]:
        fixtures = await self.fixtures(competition_id, season_id)
        seen: dict[str, dict] = {}
        for f in fixtures:
            seen[f["home"]["id"]] = f["home"]
            seen[f["away"]["id"]] = f["away"]
        return sorted(seen.values(), key=lambda t: t["name"])

    # MARK: - Datasets

    async def dataset(self, competition_id: int, season_id: int, competition_name: str, team_id: int) -> dict:
        fixtures = await self.fixtures(competition_id, season_id)
        team_fixtures = [
            f for f in fixtures
            if f["home"]["id"] == f"sb-{team_id}" or f["away"]["id"] == f"sb-{team_id}"
        ]
        team = self._find_team(team_fixtures, team_id)
        profiles = await ensure_competition_profiles(
            self.client, competition_id, season_id, competition_name, max_matches=self.max_matches
        )
        players = [p for p in profiles if p["teamName"] == team["name"]]
        players.sort(key=lambda p: p["totals"]["minutes"], reverse=True)
        return {
            "team": team,
            "competition": self._competition(competition_id, season_id, competition_name),
            "fixtures": team_fixtures,
            "players": players,
        }

    # MARK: - Analytics

    async def match_analysis(self, competition_id: int, season_id: int, match_id: int) -> dict:
        fixtures = await self.fixtures(competition_id, season_id)
        meta = next((f for f in fixtures if f["id"] == match_id), None)
        if meta is None:
            raise LookupError("Match not found in this competition season.")

        events = await self.client.events(match_id)
        lineups = await self.client.lineups(match_id)
        home_id = self._team_id(meta["home"]["id"])
        away_id = self._team_id(meta["away"]["id"])
        stats = analysis.match_team_stats(events, home_id, away_id)

        return {
            "match": meta,
            "home": {"team": meta["home"], "stats": stats[home_id], "players": analysis.player_ratings(events, lineups, home_id)},
            "away": {"team": meta["away"], "stats": stats[away_id], "players": analysis.player_ratings(events, lineups, away_id)},
            "shots": analysis.shots(events),
            "momentum": analysis.momentum(events, home_id, away_id),
        }

    async def team_analysis(self, competition_id: int, season_id: int, competition_name: str, team_id: int) -> dict:
        fixtures = await self.fixtures(competition_id, season_id)
        team_fixtures = [
            f for f in fixtures
            if f["home"]["id"] == f"sb-{team_id}" or f["away"]["id"] == f"sb-{team_id}"
        ]
        team = self._find_team(team_fixtures, team_id)
        season_stats = await analysis.team_season_stats(
            self.client, competition_id, season_id, max_matches=self.max_matches
        )
        profiles = await ensure_competition_profiles(
            self.client, competition_id, season_id, competition_name, max_matches=self.max_matches
        )
        squad = [p for p in profiles if p["teamName"] == team["name"]]
        squad.sort(key=lambda p: p["totals"]["minutes"], reverse=True)

        return {
            "team": team,
            "competition": self._competition(competition_id, season_id, competition_name),
            "stats": season_stats.get(str(team_id), {}),
            "players": squad[:12],
            "fixtures": team_fixtures,
        }

    # MARK: - Background pool job

    def start_build(self, selections: list[dict], force: bool = False) -> dict:
        if redis_available():
            job = pool_queue().enqueue(build_pool_job, selections, force, job_timeout=3600, result_ttl=3600)
            self._job = {"jobId": job.id, "status": "queued", "progress": 0.0, "message": "Queued…", "playerCount": self._pool_count()}
            return self._job

        if self._job_task and not self._job_task.done():
            self._job_task.cancel()
        self._job = {"jobId": "inline", "status": "running", "progress": 0.0, "message": "Starting…", "playerCount": self._pool_count()}
        self._job_task = asyncio.create_task(self._run_inline(selections, force))
        return self._job

    async def _run_inline(self, selections: list[dict], force: bool) -> None:
        try:
            def progress(fraction: float, message: str) -> None:
                self._job["progress"] = fraction
                self._job["message"] = message

            profiles = await build_pool_profiles(self.client, selections, force=force, progress=progress, max_matches=self.max_matches)
            write_json_atomic(POOL_FILE, profiles)
            self._job.update({"status": "ready", "progress": 1.0, "message": f"Pool ready · {len(profiles)} players", "playerCount": len(profiles)})
        except asyncio.CancelledError:
            self._job.update({"status": "idle", "message": "Cancelled"})
            raise
        except Exception as error:  # noqa: BLE001
            self._job.update({"status": "failed", "message": str(error)})

    def job_status(self, job_id: str | None = None) -> dict:
        if not job_id or job_id == "inline":
            if self._job.get("status") == "ready":
                self._job["playerCount"] = self._pool_count()
            return self._job

        try:
            from rq.job import Job

            from .taskqueue import redis_client

            job = Job.fetch(job_id, connection=redis_client())
        except Exception:  # noqa: BLE001
            return {"jobId": job_id, "status": "idle", "progress": 0.0, "message": "Unknown job", "playerCount": self._pool_count()}

        meta = job.meta or {}
        status = _STATUS_MAP.get(str(job.get_status()), "running")
        result = {
            "jobId": job_id,
            "status": status,
            "progress": float(meta.get("progress", 1.0 if status == "ready" else 0.0)),
            "message": meta.get("message", ""),
            "playerCount": int(meta.get("playerCount", self._pool_count())),
        }
        if status == "failed":
            result["message"] = meta.get("message") or str(job.exc_info or "Build failed")
        return result

    def warmup(self) -> list[dict]:
        """Enqueue cache warm-up for the popular leagues."""
        if not redis_available():
            return []
        queue = pool_queue()
        selections = POPULAR_LEAGUES
        job = queue.enqueue(warm_competitions_job, selections, job_timeout=3600, result_ttl=600)
        return [{"jobId": job.id, "selections": selections}]

    # MARK: - Helpers

    @staticmethod
    def _team_id(team_ref: str) -> int:
        return int(team_ref.split("-", 1)[1])

    def _find_team(self, fixtures: list[dict], team_id: int) -> dict:
        target = f"sb-{team_id}"
        for f in fixtures:
            if f["home"]["id"] == target:
                return f["home"]
            if f["away"]["id"] == target:
                return f["away"]
        return _team(team_id, f"Team {team_id}")

    def _competition(self, competition_id: int, season_id: int, name: str) -> dict:
        return {
            "competitionID": competition_id,
            "seasonID": season_id,
            "name": name,
            "country": "",
            "gender": "",
            "seasonName": "",
        }

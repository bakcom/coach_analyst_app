"""Post-game (single match) and team season analytics derived from StatsBomb
events. Shared by the API and reused for the app's Post-Game and Team Analysis
screens.
"""

from __future__ import annotations

import asyncio
import json

from .aggregate import contributions
from .builder import CHUNK, DEFAULT_MAX_MATCHES, team_cache_path
from .statsbomb import StatsBombClient
from .storage import write_json_atomic

# Team metric descriptors used by the app's style radar.
TEAM_METRICS = [
    "possession", "passAccuracy", "passes", "progressivePasses",
    "finalThirdPasses", "shots", "xg", "goals", "ppda", "highTurnovers",
]


def _blank() -> dict:
    return {
        "posEvents": 0,
        "passes": 0, "passesCompleted": 0, "progressivePasses": 0, "finalThirdPasses": 0,
        "shots": 0, "shotsOnTarget": 0, "xg": 0.0, "goals": 0,
        "pressures": 0, "tackles": 0, "interceptions": 0,
        "ballRecoveries": 0, "highTurnovers": 0, "boxEntries": 0,
    }


def _accumulate_team(event: dict, raw: dict) -> None:
    etype = event.get("type", {}).get("name", "")
    location = event.get("location")

    if etype == "Pass":
        p = event.get("pass") or {}
        raw["passes"] += 1
        if p.get("outcome") is None:
            raw["passesCompleted"] += 1
        end = p.get("end_location")
        if end and location:
            if end[0] - location[0] >= 10:
                raw["progressivePasses"] += 1
            if end[0] >= 80:
                raw["finalThirdPasses"] += 1
            if end[0] >= 102 and 18 <= end[1] <= 62:
                raw["boxEntries"] += 1

    elif etype == "Shot":
        s = event.get("shot") or {}
        raw["shots"] += 1
        raw["xg"] += float(s.get("statsbomb_xg") or 0.0)
        outcome = (s.get("outcome") or {}).get("name")
        if outcome == "Goal":
            raw["goals"] += 1
        if outcome in ("Goal", "Saved"):
            raw["shotsOnTarget"] += 1

    elif etype == "Pressure":
        raw["pressures"] += 1

    elif etype == "Interception":
        raw["interceptions"] += 1

    elif etype == "Duel":
        if (event.get("duel") or {}).get("type", {}).get("name") == "Tackle":
            raw["tackles"] += 1

    elif etype == "Ball Recovery":
        raw["ballRecoveries"] += 1
        if location and location[0] >= 60:
            raw["highTurnovers"] += 1


def _derive(raw: dict, opponent: dict, total_pos: int) -> dict:
    defensive_actions = raw["pressures"] + raw["tackles"] + raw["interceptions"]
    return {
        "possession": round(100 * raw["posEvents"] / total_pos, 1) if total_pos else 0.0,
        "passAccuracy": round(raw["passesCompleted"] / raw["passes"], 3) if raw["passes"] else 0.0,
        "passes": raw["passes"],
        "passesCompleted": raw["passesCompleted"],
        "progressivePasses": raw["progressivePasses"],
        "finalThirdPasses": raw["finalThirdPasses"],
        "boxEntries": raw["boxEntries"],
        "shots": raw["shots"],
        "shotsOnTarget": raw["shotsOnTarget"],
        "xg": round(raw["xg"], 2),
        "goals": raw["goals"],
        "ppda": round(opponent["passes"] / defensive_actions, 2) if defensive_actions else 0.0,
        "pressures": raw["pressures"],
        "interceptions": raw["interceptions"],
        "tackles": raw["tackles"],
        "highTurnovers": raw["highTurnovers"],
        # Season-only fields, present (with neutral values) so match and season
        # payloads share one shape.
        "matches": 1,
        "xgFor": round(raw["xg"], 2),
        "recent": [],
    }


def match_team_stats(events: list[dict], home_id: int, away_id: int) -> dict[int, dict]:
    raw = {home_id: _blank(), away_id: _blank()}
    for event in events:
        possession_team = (event.get("possession_team") or {}).get("id")
        if possession_team in raw:
            raw[possession_team]["posEvents"] += 1
        team = (event.get("team") or {}).get("id")
        if team in raw:
            _accumulate_team(event, raw[team])

    total_pos = raw[home_id]["posEvents"] + raw[away_id]["posEvents"]
    return {
        home_id: _derive(raw[home_id], raw[away_id], total_pos),
        away_id: _derive(raw[away_id], raw[home_id], total_pos),
    }


def shots(events: list[dict]) -> list[dict]:
    output = []
    for event in events:
        if event.get("type", {}).get("name") != "Shot":
            continue
        s = event.get("shot") or {}
        location = event.get("shot", {}).get("end_location") or event.get("location") or [0, 0]
        output.append({
            "minute": event.get("minute", 0),
            "x": location[0],
            "y": location[1],
            "xg": round(float(s.get("statsbomb_xg") or 0.0), 3),
            "outcome": (s.get("outcome") or {}).get("name", "Unknown"),
            "teamID": event["team"]["id"],
            "player": (event.get("player") or {}).get("name", ""),
        })
    return output


def momentum(events: list[dict], home_id: int, away_id: int, bucket: int = 5) -> list[dict]:
    buckets: dict[int, dict] = {}
    for event in events:
        if event.get("type", {}).get("name") != "Shot":
            continue
        minute = event.get("minute", 0)
        index = (minute // bucket) * bucket
        entry = buckets.setdefault(index, {"minute": index, "home": 0.0, "away": 0.0})
        xg = float((event.get("shot") or {}).get("statsbomb_xg") or 0.0)
        if event["team"]["id"] == home_id:
            entry["home"] += xg
        elif event["team"]["id"] == away_id:
            entry["away"] += xg
    return [
        {"minute": k, "home": round(v["home"], 2), "away": round(v["away"], 2)}
        for k, v in sorted(buckets.items())
    ]


def player_ratings(events: list[dict], lineups: list[dict], team_id: int) -> list[dict]:
    rated = []
    for contribution in contributions(events, lineups):
        if contribution["teamID"] != team_id:
            continue
        totals = contribution["totals"]
        impact = (
            totals["goals"] * 3.0 + totals["xg"] * 2.0 + totals["assists"] * 2.0
            + totals["keyPasses"] * 0.6 + totals["progressivePasses"] * 0.06
            + totals["pressures"] * 0.02
        )
        rated.append({
            "playerID": f"sb-{contribution['playerID']}",
            "name": contribution["name"],
            "minutes": round(contribution["minutes"]),
            "goals": int(totals["goals"]),
            "assists": int(totals["assists"]),
            "xg": round(totals["xg"], 2),
            "keyPasses": int(totals["keyPasses"]),
            "impact": round(impact, 1),
        })
    rated.sort(key=lambda r: r["impact"], reverse=True)
    return rated


def _aggregate_season(match_stats: list[dict], recent: list[dict]) -> dict:
    count = max(len(match_stats), 1)

    def avg(key: str) -> float:
        return sum(s.get(key, 0.0) for s in match_stats) / count

    return {
        "matches": len(match_stats),
        "possession": round(avg("possession"), 1),
        "passAccuracy": round(avg("passAccuracy"), 3),
        "passes": round(avg("passes"), 1),
        "progressivePasses": round(avg("progressivePasses"), 1),
        "finalThirdPasses": round(avg("finalThirdPasses"), 1),
        "boxEntries": round(avg("boxEntries"), 1),
        "shots": round(avg("shots"), 1),
        "shotsOnTarget": round(avg("shotsOnTarget"), 1),
        "xg": round(avg("xg"), 2),
        "goals": round(avg("goals"), 2),
        "ppda": round(avg("ppda"), 2),
        "pressures": round(avg("pressures"), 1),
        "interceptions": round(avg("interceptions"), 1),
        "tackles": round(avg("tackles"), 1),
        "highTurnovers": round(avg("highTurnovers"), 1),
        "xgFor": round(sum(s.get("xg", 0.0) for s in match_stats), 1),
        "recent": sorted(recent, key=lambda item: item["date"])[-6:],
    }


async def team_season_stats(
    client: StatsBombClient,
    competition_id: int,
    season_id: int,
    force: bool = False,
    max_matches: int = DEFAULT_MAX_MATCHES,
) -> dict[str, dict]:
    """Per-team season aggregates for a whole competition, cached on disk."""
    path = team_cache_path(competition_id, season_id)
    if not force and path.exists():
        return json.loads(path.read_text())

    matches = (await client.matches(competition_id, season_id))[:max_matches]
    per_team: dict[str, list[dict]] = {}
    recent: dict[str, list[dict]] = {}

    for start in range(0, len(matches), CHUNK):
        chunk = matches[start:start + CHUNK]

        async def one(match: dict):
            return match, await client.events(match["match_id"])

        for match, events in await asyncio.gather(*(one(m) for m in chunk)):
            home_id = match["home_team"]["home_team_id"]
            away_id = match["away_team"]["away_team_id"]
            stats = match_team_stats(events, home_id, away_id)
            for team_id, opponent_id in ((home_id, away_id), (away_id, home_id)):
                per_team.setdefault(str(team_id), []).append(stats[team_id])
                is_home = team_id == home_id
                recent.setdefault(str(team_id), []).append({
                    "opponent": (match["away_team"] if is_home else match["home_team"])[f"{'away' if is_home else 'home'}_team_name"],
                    "home": is_home,
                    "goalsFor": match["home_score"] if is_home else match["away_score"],
                    "goalsAgainst": match["away_score"] if is_home else match["home_score"],
                    "xg": stats[team_id]["xg"],
                    "date": match["match_date"],
                })

    data = {team_id: _aggregate_season(stats, recent.get(team_id, [])) for team_id, stats in per_team.items()}
    try:
        write_json_atomic(path, data)
    except OSError:
        pass
    return data

"""Shared, stateless build logic used by both the API process and the queue
worker: per-competition aggregation with an incremental disk cache, and the
merge step that produces the pooled player list.
"""

from __future__ import annotations

import asyncio
import json

from .aggregate import TOTAL_KEYS, contributions
from .config import CACHE_DIR, MAX_MATCHES_PER_COMPETITION
from .metrics import add_totals, build_profiles
from .statsbomb import StatsBombClient
from .storage import write_json_atomic

POOL_CACHE_DIR = CACHE_DIR / "pool_cache"
TEAM_CACHE_DIR = CACHE_DIR / "team_cache"
CHUNK = 6
DEFAULT_MAX_MATCHES = MAX_MATCHES_PER_COMPETITION


def competition_cache_path(competition_id: int, season_id: int):
    return POOL_CACHE_DIR / f"{competition_id}-{season_id}.json"


def team_cache_path(competition_id: int, season_id: int):
    return TEAM_CACHE_DIR / f"{competition_id}-{season_id}.json"


def merge_profiles(profile_lists: list[list[dict]]) -> list[dict]:
    """Merge per-competition profiles, combining players who appear in more
    than one competition and attributing each to the competition (and role)
    they played most in."""
    accs: dict[str, dict] = {}
    for profiles in profile_lists:
        for profile in profiles:
            acc = accs.get(profile["playerID"])
            if acc is None:
                acc = {
                    "name": profile["name"],
                    "teamName": profile["teamName"],
                    "position": profile["primaryPosition"],
                    "best_position_minutes": -1.0,
                    "totals": {key: 0.0 for key in TOTAL_KEYS},
                    "competition_minutes": {},
                    "competition_names": {},
                    "group_minutes": {},
                }
                accs[profile["playerID"]] = acc

            add_totals(acc["totals"], profile["totals"])
            minutes = profile["totals"].get("minutes", 0.0)
            comp_id = profile["competitionID"]
            acc["competition_minutes"][comp_id] = acc["competition_minutes"].get(comp_id, 0.0) + minutes
            acc["competition_names"][comp_id] = profile["competitionName"]
            group = profile["group"]
            acc["group_minutes"][group] = acc["group_minutes"].get(group, 0.0) + minutes
            if minutes >= acc["best_position_minutes"]:
                acc["best_position_minutes"] = minutes
                acc["position"] = profile["primaryPosition"]
                acc["name"] = profile["name"]
                acc["teamName"] = profile["teamName"]

    merged = []
    for player_id, acc in accs.items():
        comp_id = max(acc["competition_minutes"], key=acc["competition_minutes"].get)
        group = max(acc["group_minutes"], key=acc["group_minutes"].get)
        merged.append({
            "playerID": player_id,
            "name": acc["name"],
            "teamName": acc["teamName"],
            "competitionID": comp_id,
            "competitionName": acc["competition_names"].get(comp_id, ""),
            "group": group,
            "primaryPosition": acc["position"],
            "totals": acc["totals"],
        })
    return merged


async def analyze_matches(client: StatsBombClient, match_ids: list[int], progress=None) -> list[list[dict]]:
    results: list[list[dict]] = []
    total = max(len(match_ids), 1)
    for start in range(0, len(match_ids), CHUNK):
        chunk = match_ids[start:start + CHUNK]

        async def one(match_id: int):
            lineups = await client.lineups(match_id)
            events = await client.events(match_id)
            return contributions(events, lineups)

        results.extend(await asyncio.gather(*(one(mid) for mid in chunk)))
        if progress:
            progress(min(len(results), total) / total)
    return results


async def ensure_competition_profiles(
    client: StatsBombClient,
    competition_id: int,
    season_id: int,
    name: str,
    force: bool = False,
    progress=None,
    max_matches: int = DEFAULT_MAX_MATCHES,
) -> list[dict]:
    """All player profiles for a competition season, from cache when present."""
    path = competition_cache_path(competition_id, season_id)
    if not force and path.exists():
        if progress:
            progress(1.0)
        return json.loads(path.read_text())

    matches = await client.matches(competition_id, season_id)
    match_ids = [m["match_id"] for m in matches][:max_matches]
    results = await analyze_matches(client, match_ids, progress)
    profiles = build_profiles(results, competition_id, name)
    try:
        write_json_atomic(path, profiles)
    except OSError:
        pass
    return profiles


async def build_pool_profiles(
    client: StatsBombClient,
    selections: list[dict],
    force: bool = False,
    progress=None,
    max_matches: int = DEFAULT_MAX_MATCHES,
) -> list[dict]:
    count = max(len(selections), 1)
    profile_lists: list[list[dict]] = []
    for index, selection in enumerate(selections):
        competition_id = selection["competitionID"]
        season_id = selection["seasonID"]
        name = selection.get("name") or f"{competition_id}/{season_id}"

        def report(fraction: float, index: int = index) -> None:
            if progress:
                progress((index + fraction) / count, ("Loading " if competition_cache_path(competition_id, season_id).exists() and not force else "Analysing ") + name)

        profile_lists.append(
            await ensure_competition_profiles(client, competition_id, season_id, name, force, report, max_matches)
        )
    return merge_profiles(profile_lists)

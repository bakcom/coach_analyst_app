"""Turn StatsBomb lineups + events into per-player metric totals.

This is a faithful port of the Swift `StatsBombAggregator` so the BFF and the
on-device backend produce identical numbers.
"""

from __future__ import annotations

TOTAL_KEYS = [
    "minutes", "goals", "xg", "shots", "assists", "keyPasses",
    "passesAttempted", "passesCompleted", "progressivePasses", "finalThirdPasses",
    "carries", "progressiveCarries", "dribblesCompleted",
    "tacklesWon", "interceptions", "clearances", "ballRecoveries",
    "pressures", "touchesInBox", "saves",
]


def empty_totals(minutes: float = 0.0) -> dict:
    totals = {key: 0.0 for key in TOTAL_KEYS}
    totals["minutes"] = float(minutes)
    return totals


def _parse_clock(clock: str) -> float:
    parts = clock.split(":")
    if len(parts) != 2:
        return 0.0
    return int(parts[0]) + int(parts[1]) / 60.0


def _position_minutes(positions: list[dict], match_length: float) -> tuple[float, str]:
    total = 0.0
    by_position: dict[str, float] = {}
    for position in positions:
        start = _parse_clock(position.get("from", "00:00"))
        end = _parse_clock(position["to"]) if position.get("to") else match_length
        duration = max(0.0, end - start)
        total += duration
        name = position.get("position", "Unknown")
        by_position[name] = by_position.get(name, 0.0) + duration
    primary = max(by_position, key=by_position.get) if by_position else "Unknown"
    return total, primary


def position_group(position_name: str) -> str:
    n = position_name.lower()
    if "goalkeeper" in n:
        return "Goalkeeper"
    if "back" in n:
        return "Defender"
    if "midfield" in n:
        return "Midfielder"
    if "wing" in n:
        return "Forward"
    if "forward" in n or "striker" in n:
        return "Forward"
    return "Midfielder"


def _in_box(location) -> bool:
    return bool(location) and len(location) >= 2 and location[0] >= 102 and 18 <= location[1] <= 62


def _accumulate(event: dict, assist_ids: set[str], totals: dict) -> None:
    etype = event.get("type", {}).get("name", "")
    location = event.get("location")
    in_box = _in_box(location)

    if etype == "Pass":
        p = event.get("pass") or {}
        totals["passesAttempted"] += 1
        if p.get("outcome") is None:
            totals["passesCompleted"] += 1
        end = p.get("end_location")
        if end and location:
            if end[0] - location[0] >= 10:
                totals["progressivePasses"] += 1
            if end[0] >= 80:
                totals["finalThirdPasses"] += 1
        if p.get("assisted_shot_id"):
            totals["keyPasses"] += 1
        if p.get("goal_assist") or event.get("id") in assist_ids:
            totals["assists"] += 1
        if in_box:
            totals["touchesInBox"] += 1

    elif etype == "Shot":
        s = event.get("shot") or {}
        totals["shots"] += 1
        totals["xg"] += float(s.get("statsbomb_xg") or 0.0)
        if (s.get("outcome") or {}).get("name") == "Goal":
            totals["goals"] += 1
        if in_box:
            totals["touchesInBox"] += 1

    elif etype == "Carry":
        c = event.get("carry") or {}
        totals["carries"] += 1
        end = c.get("end_location")
        if end and location and end[0] - location[0] >= 10:
            totals["progressiveCarries"] += 1
        if in_box:
            totals["touchesInBox"] += 1

    elif etype == "Dribble":
        if (event.get("dribble") or {}).get("outcome", {}).get("name") == "Complete":
            totals["dribblesCompleted"] += 1

    elif etype == "Duel":
        d = event.get("duel") or {}
        dtype = (d.get("type") or {}).get("name", "")
        outcome = (d.get("outcome") or {}).get("name", "")
        if dtype == "Tackle" and outcome in ("Won", "Success In Play"):
            totals["tacklesWon"] += 1

    elif etype == "Interception":
        totals["interceptions"] += 1

    elif etype == "Clearance":
        totals["clearances"] += 1

    elif etype == "Ball Recovery":
        totals["ballRecoveries"] += 1

    elif etype == "Pressure":
        totals["pressures"] += 1

    elif etype == "Goal Keeper":
        if "Saved" in ((event.get("goalkeeper") or {}).get("type") or {}).get("name", ""):
            totals["saves"] += 1


def contributions(events: list[dict], lineups: list[dict]) -> list[dict]:
    match_length = float(max((e.get("minute", 0) for e in events), default=90))
    by_player: dict[int, dict] = {}

    for team in lineups:
        for player in team.get("lineup", []):
            minutes, best_position = _position_minutes(player.get("positions", []), match_length)
            by_player[player["player_id"]] = {
                "playerID": player["player_id"],
                "name": player.get("player_nickname") or player.get("player_name", ""),
                "teamID": team["team_id"],
                "teamName": team["team_name"],
                "minutes": minutes,
                "positionName": best_position,
                "group": position_group(best_position),
                "totals": empty_totals(minutes),
            }

    assist_ids = {
        e["shot"]["key_pass_id"]
        for e in events
        if e.get("type", {}).get("name") == "Shot"
        and (e.get("shot") or {}).get("outcome", {}).get("name") == "Goal"
        and (e.get("shot") or {}).get("key_pass_id")
    }

    for event in events:
        player = event.get("player")
        if not player:
            continue
        pid = player["id"]
        contribution = by_player.get(pid) or {
            "playerID": pid,
            "name": player.get("name", ""),
            "teamID": event["team"]["id"],
            "teamName": event["team"]["name"],
            "minutes": 0.0,
            "positionName": "Unknown",
            "group": "Midfielder",
            "totals": empty_totals(0.0),
        }
        _accumulate(event, assist_ids, contribution["totals"])
        by_player[pid] = contribution

    return list(by_player.values())

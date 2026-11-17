"""Generate deterministic synthetic StatsBomb fixtures for the parity harness.

The Ruby and Python runners both read the same `fixtures.json`, so they are fed
byte-identical inputs. Run:  python3 parity/fixtures.py -o tmp/parity/fixtures.json
"""

from __future__ import annotations

import argparse
import json
import random

TOTAL_KEYS = [
    "minutes", "goals", "xg", "shots", "assists", "keyPasses",
    "passesAttempted", "passesCompleted", "progressivePasses", "finalThirdPasses",
    "carries", "progressiveCarries", "dribblesCompleted",
    "tacklesWon", "interceptions", "clearances", "ballRecoveries",
    "pressures", "touchesInBox", "saves",
]

POSITION_NAMES = [
    "Goalkeeper", "Right Back", "Left Center Back", "Center Midfield",
    "Right Wing", "Left Wing", "Center Forward", "Right Center Back",
    "Left Midfield", "Striker", "Unknown", "Left Wing Back",
]


def empty_totals(minutes: float = 0.0) -> dict:
    totals = {key: 0.0 for key in TOTAL_KEYS}
    totals["minutes"] = float(minutes)
    return totals


def make_profile(player_id: str, group: str, minutes: float, competition_id: int, **totals) -> dict:
    values = empty_totals(minutes)
    values.update(totals)
    return {
        "playerID": player_id,
        "name": player_id,
        "teamName": "Team",
        "competitionID": competition_id,
        "competitionName": f"Comp {competition_id}",
        "group": group,
        "primaryPosition": "X",
        "totals": values,
    }


def build_events(lineups):
    rng = random.Random(20240517)
    home_id, away_id = 1, 2
    home_players = [p["player_id"] for p in lineups[0]["lineup"]]
    away_players = [p["player_id"] for p in lineups[1]["lineup"]]
    events = []

    def add(minute, etype, team_id, player_id, **extra):
        event = {
            "id": f"e{len(events)}",
            "minute": minute,
            "type": {"name": etype},
            "team": {"id": team_id, "name": lineups[0 if team_id == home_id else 1]["team_name"]},
            "possession_team": {"id": team_id},
            "player": {"id": player_id, "name": f"Player {player_id}"},
        }
        event.update(extra)
        events.append(event)

    for i in range(40):
        minute = 1 + i
        team_id = home_id if i % 2 == 0 else away_id
        players = home_players if team_id == home_id else away_players
        player = rng.choice(players)
        start = [rng.randint(10, 100), rng.randint(5, 75)]
        kind = rng.random()

        if kind < 0.40:
            end = [start[0] + rng.randint(-5, 25), start[1] + rng.randint(-20, 20)]
            outcome = None if rng.random() < 0.8 else {"name": "Incomplete"}
            add(minute, "Pass", team_id, player, location=start,
                **{"pass": {"end_location": end, "outcome": outcome,
                            "assisted_shot_id": "x" if rng.random() < 0.2 else None}})
        elif kind < 0.55:
            add(minute, "Carry", team_id, player, location=start,
                carry={"end_location": [start[0] + rng.randint(-5, 20), start[1]]})
        elif kind < 0.65:
            add(minute, "Shot", team_id, player, location=start,
                shot={"statsbomb_xg": round(rng.uniform(0.02, 0.7), 3),
                      "outcome": {"name": rng.choice(["Goal", "Saved", "Off T", "Blocked"])},
                      "key_pass_id": f"k{len(events)}"})
        elif kind < 0.72:
            add(minute, "Dribble", team_id, player, location=start,
                dribble={"outcome": {"name": rng.choice(["Complete", "Incomplete"])}})
        elif kind < 0.80:
            add(minute, "Duel", team_id, player, location=start,
                duel={"type": {"name": "Tackle"},
                      "outcome": {"name": rng.choice(["Won", "Lost", "Success In Play"])}})
        elif kind < 0.86:
            add(minute, "Pressure", team_id, player, location=start)
        elif kind < 0.91:
            add(minute, "Interception", team_id, player, location=start)
        elif kind < 0.95:
            add(minute, "Clearance", team_id, player, location=start)
        elif kind < 0.98:
            add(minute, "Ball Recovery", team_id, player, location=start)
        else:
            add(minute, "Goal Keeper", team_id, player, location=start,
                goalkeeper={"type": {"name": rng.choice(["Shot Saved", "Collected"])}})

    return events


def build():
    home_lineup = {
        "team_id": 1,
        "team_name": "Home FC",
        "lineup": [
            {"player_id": 101, "player_name": "Keeper One", "player_nickname": None,
             "positions": [{"position": "Goalkeeper", "from": "00:00", "to": None}]},
            {"player_id": 102, "player_name": "Back Two", "player_nickname": "B2",
             "positions": [
                 {"position": "Right Back", "from": "00:00", "to": "60:00"},
                 {"position": "Right Center Back", "from": "60:00", "to": None},
             ]},
            {"player_id": 103, "player_name": "Mid Three", "player_nickname": None,
             "positions": [{"position": "Center Midfield", "from": "00:00", "to": None}]},
            {"player_id": 104, "player_name": "Forward Four", "player_nickname": None,
             "positions": [{"position": "Center Forward", "from": "00:00", "to": None}]},
        ],
    }
    away_lineup = {
        "team_id": 2,
        "team_name": "Away United",
        "lineup": [
            {"player_id": 201, "player_name": "Away Keeper", "player_nickname": None,
             "positions": [{"position": "Goalkeeper", "from": "00:00", "to": None}]},
            {"player_id": 202, "player_name": "Away Back", "player_nickname": None,
             "positions": [{"position": "Left Center Back", "from": "00:00", "to": None}]},
            {"player_id": 203, "player_name": "Away Mid", "player_nickname": None,
             "positions": [{"position": "Left Midfield", "from": "00:00", "to": None}]},
            {"player_id": 204, "player_name": "Away Striker", "player_nickname": "S9",
             "positions": [{"position": "Striker", "from": "00:00", "to": None}]},
        ],
    }
    lineups = [home_lineup, away_lineup]

    pool = [make_profile(f"sb-p{i}", "Forward", 900, competition_id=1 + (i % 2),
                         goals=float(i % 7), xg=float(i) * 0.3, shots=float(i * 2),
                         assists=float(i % 3), keyPasses=float(i),
                         dribblesCompleted=float(i % 4), touchesInBox=float(i * 2),
                         progressiveCarries=float(i), pressures=float(i * 3))
            for i in range(1, 13)]
    target = make_profile("sb-target", "Forward", 900, competition_id=1,
                          goals=9.0, xg=7.5, shots=40.0, assists=5.0, keyPasses=20.0,
                          dribblesCompleted=12.0, touchesInBox=55.0,
                          progressiveCarries=18.0, pressures=60.0)
    candidate = make_profile("sb-cand", "Forward", 900, competition_id=2,
                             goals=3.0, xg=4.0, shots=22.0, assists=2.0, keyPasses=9.0,
                             dribblesCompleted=5.0, touchesInBox=30.0,
                             progressiveCarries=8.0, pressures=44.0)

    profiles_a = [make_profile("sb-x", "Midfielder", 900, competition_id=1,
                               passesAttempted=600.0, passesCompleted=540.0),
                  make_profile("sb-y", "Defender", 400, competition_id=1,
                               tacklesWon=8.0, interceptions=6.0)]
    profiles_b = [make_profile("sb-x", "Midfielder", 200, competition_id=2,
                               passesAttempted=150.0, passesCompleted=130.0),
                  make_profile("sb-z", "Forward", 300, competition_id=2,
                               goals=2.0, xg=1.4)]

    recent = [
        {"opponent": "A", "home": True, "goalsFor": 2, "goalsAgainst": 1, "xg": 1.4, "date": "2024-01-01"},
        {"opponent": "B", "home": False, "goalsFor": 0, "goalsAgainst": 0, "xg": 0.6, "date": "2024-01-08"},
        {"opponent": "C", "home": True, "goalsFor": 3, "goalsAgainst": 2, "xg": 2.1, "date": "2024-01-15"},
    ]

    return {
        "home_id": 1,
        "away_id": 2,
        "lineups": lineups,
        "events": build_events(lineups),
        "pool": pool,
        "target": target,
        "candidate": candidate,
        "profiles_a": profiles_a,
        "profiles_b": profiles_b,
        "recent": recent,
        "position_names": POSITION_NAMES,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-o", "--output", required=True)
    args = parser.parse_args()
    with open(args.output, "w") as handle:
        json.dump(build(), handle, indent=2)
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()

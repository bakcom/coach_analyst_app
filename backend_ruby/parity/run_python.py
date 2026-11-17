"""Run the FastAPI backend's pure analytics on parity fixtures and emit JSON.

Usage:  python3 parity/run_python.py <fixtures.json> -o <output.json>
"""

from __future__ import annotations

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BACKEND = os.path.abspath(os.path.join(HERE, "..", "..", "backend"))
sys.path.insert(0, BACKEND)

from app import aggregate, analysis, builder, metrics  # noqa: E402


def compute(data):
    events = data["events"]
    lineups = data["lineups"]
    home_id = data["home_id"]
    away_id = data["away_id"]

    team_stats = analysis.match_team_stats(events, home_id, away_id)
    stringified = {str(k): v for k, v in team_stats.items()}

    return {
        "contributions": aggregate.contributions(events, lineups),
        "team_stats": stringified,
        "shots": analysis.shots(events),
        "momentum": analysis.momentum(events, home_id, away_id),
        "ratings_home": analysis.player_ratings(events, lineups, home_id),
        "season": analysis._aggregate_season(
            [team_stats[home_id], team_stats[away_id]], data["recent"]
        ),
        "similar": metrics.similar(data["target"], data["pool"],
                                   other_competitions_only=True, limit=5, min_minutes=0.0),
        "comparison": metrics.comparison(data["target"], data["candidate"], data["pool"], min_minutes=0.0),
        "merged": builder.merge_profiles([data["profiles_a"], data["profiles_b"]]),
        "position_groups": {name: aggregate.position_group(name) for name in data["position_names"]},
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("fixtures")
    parser.add_argument("-o", "--output", required=True)
    args = parser.parse_args()

    with open(args.fixtures) as handle:
        data = json.load(handle)
    with open(args.output, "w") as handle:
        json.dump(compute(data), handle, indent=2, sort_keys=True)
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()

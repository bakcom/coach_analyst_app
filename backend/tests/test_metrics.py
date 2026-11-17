"""Pure-function tests for the aggregation and similarity maths (no network)."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import metrics  # noqa: E402
from app.aggregate import contributions, empty_totals  # noqa: E402


def make_profile(player_id: str, group: str, minutes: float, competition_id: int = 1, **totals) -> dict:
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


def test_metric_value_is_per_90():
    totals = empty_totals(90)
    totals["goals"] = 3
    assert metrics.metric_value("goals", totals, 90) == 3.0
    assert metrics.metric_value("goals", totals, 45) == 6.0


def test_pass_accuracy_is_a_ratio():
    totals = {"passesAttempted": 10, "passesCompleted": 5}
    assert metrics.metric_value("passAccuracy", totals, 90) == 0.5
    assert metrics.metric_value("passAccuracy", {"passesAttempted": 0}, 90) == 0.0


def test_similar_respects_group_and_competition():
    target = make_profile("p1", "Midfielder", 900, competition_id=1,
                          passesAttempted=900, passesCompleted=810, progressivePasses=120)
    pool = [
        target,
        make_profile("same_comp", "Midfielder", 900, competition_id=1,
                     passesAttempted=880, passesCompleted=800, progressivePasses=110),
        make_profile("other_comp", "Midfielder", 900, competition_id=2,
                     passesAttempted=870, passesCompleted=790, progressivePasses=115),
        make_profile("wrong_group", "Defender", 900, competition_id=2, tacklesWon=50),
    ]
    result = metrics.similar(target, pool, other_competitions_only=True, min_minutes=0)
    ids = [item["profile"]["playerID"] for item in result["similar"]]
    assert "other_comp" in ids
    assert "same_comp" not in ids  # same competition excluded
    assert "wrong_group" not in ids  # different role excluded


def test_comparison_normalises_to_percentiles():
    target = make_profile("t", "Forward", 900, goals=20, shots=80)
    candidate = make_profile("c", "Forward", 900, goals=4, shots=30)
    pool = [make_profile(f"p{i}", "Forward", 900, goals=i, shots=i * 3) for i in range(1, 11)]
    rows = metrics.comparison(target, candidate, pool, min_minutes=0)
    goals = next(row for row in rows if row["metric"] == "goals")
    assert goals["targetNormalized"] >= goals["candidateNormalized"]


def test_contributions_from_synthetic_events():
    lineups = [{
        "team_id": 1, "team_name": "A",
        "lineup": [{
            "player_id": 10, "player_name": "P", "player_nickname": None,
            "positions": [{"position": "Center Forward", "from": "00:00", "to": None}],
        }],
    }]
    events = [
        {"id": "e1", "minute": 40, "type": {"name": "Shot"}, "team": {"id": 1, "name": "A"},
         "player": {"id": 10, "name": "P"}, "location": [110, 40],
         "shot": {"statsbomb_xg": 0.5, "outcome": {"name": "Goal"}}},
        {"id": "e2", "minute": 90, "type": {"name": "Pass"}, "team": {"id": 1, "name": "A"},
         "player": {"id": 10, "name": "P"}, "location": [50, 40],
         "pass": {"end_location": [70, 40]}},
    ]
    output = contributions(events, lineups)
    assert len(output) == 1
    player = output[0]
    assert player["minutes"] == 90
    assert player["group"] == "Forward"
    assert player["totals"]["goals"] == 1
    assert player["totals"]["xg"] == 0.5
    assert player["totals"]["touchesInBox"] == 1
    assert player["totals"]["passesAttempted"] == 1
    assert player["totals"]["passesCompleted"] == 1
    assert player["totals"]["progressivePasses"] == 1

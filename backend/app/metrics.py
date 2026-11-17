"""Metric definitions, profile aggregation and the position-aware similarity
and comparison maths. Ported from the Swift `ScoutMetric` / `SimilarityEngine`.
"""

from __future__ import annotations

import math

from .aggregate import TOTAL_KEYS

METRICS_BY_GROUP = {
    "Goalkeeper": ["saves", "passAccuracy", "passesAttempted", "ballRecoveries"],
    "Defender": ["tacklesWon", "interceptions", "clearances", "ballRecoveries",
                 "passAccuracy", "progressivePasses", "pressures", "passesAttempted"],
    "Midfielder": ["passesAttempted", "passAccuracy", "progressivePasses", "finalThirdPasses",
                   "keyPasses", "carries", "progressiveCarries", "dribblesCompleted",
                   "interceptions", "pressures", "ballRecoveries"],
    "Forward": ["goals", "xg", "shots", "assists", "keyPasses",
                "dribblesCompleted", "touchesInBox", "progressiveCarries", "pressures"],
}


def metrics_for(group: str) -> list[str]:
    return METRICS_BY_GROUP.get(group, METRICS_BY_GROUP["Midfielder"])


def metric_value(metric: str, totals: dict, minutes: float) -> float:
    if metric == "passAccuracy":
        attempted = totals.get("passesAttempted", 0.0)
        return totals.get("passesCompleted", 0.0) / attempted if attempted > 0 else 0.0
    if minutes <= 0:
        return 0.0
    return totals.get(metric, 0.0) / minutes * 90.0


def add_totals(target: dict, source: dict) -> None:
    for key in TOTAL_KEYS:
        target[key] = target.get(key, 0.0) + source.get(key, 0.0)


class Accumulator:
    """Merges a player's contributions across matches and competitions."""

    def __init__(self, player_id: int, name: str, team_name: str) -> None:
        self.player_id = player_id
        self.name = name
        self.team_name = team_name
        self.totals = {key: 0.0 for key in TOTAL_KEYS}
        self.minutes_by_group: dict[str, float] = {}
        self.minutes_by_competition: dict[int, float] = {}
        self.name_by_competition: dict[int, str] = {}
        self.minutes_by_position: dict[str, float] = {}

    def add(self, contribution: dict, competition_id: int, competition_name: str) -> None:
        self.name = contribution["name"]
        self.team_name = contribution["teamName"]
        add_totals(self.totals, contribution["totals"])
        minutes = contribution["minutes"]
        group = contribution["group"]
        self.minutes_by_group[group] = self.minutes_by_group.get(group, 0.0) + minutes
        self.minutes_by_competition[competition_id] = self.minutes_by_competition.get(competition_id, 0.0) + minutes
        self.name_by_competition[competition_id] = competition_name
        pos = contribution["positionName"]
        self.minutes_by_position[pos] = self.minutes_by_position.get(pos, 0.0) + minutes

    def profile(self) -> dict:
        group = max(self.minutes_by_group, key=self.minutes_by_group.get) if self.minutes_by_group else "Midfielder"
        comp_id = max(self.minutes_by_competition, key=self.minutes_by_competition.get) if self.minutes_by_competition else 0
        position = max(self.minutes_by_position, key=self.minutes_by_position.get) if self.minutes_by_position else "Unknown"
        return {
            "playerID": f"sb-{self.player_id}",
            "name": self.name,
            "teamName": self.team_name,
            "competitionID": comp_id,
            "competitionName": self.name_by_competition.get(comp_id, ""),
            "group": group,
            "primaryPosition": position,
            "totals": self.totals,
        }


def build_profiles(
    match_contributions: list[list[dict]],
    competition_id: int,
    competition_name: str,
    team_id: int | None = None,
) -> list[dict]:
    by_player: dict[int, Accumulator] = {}
    for match in match_contributions:
        for contribution in match:
            if team_id is not None and contribution["teamID"] != team_id:
                continue
            acc = by_player.get(contribution["playerID"]) or Accumulator(
                contribution["playerID"], contribution["name"], contribution["teamName"]
            )
            acc.add(contribution, competition_id, competition_name)
            by_player[contribution["playerID"]] = acc
    return [acc.profile() for acc in by_player.values()]


# MARK: - Similarity

def similar(
    target: dict,
    pool: list[dict],
    other_competitions_only: bool = True,
    limit: int = 10,
    min_minutes: float = 270.0,
) -> dict:
    metrics = metrics_for(target["group"])

    def candidates(threshold: float) -> list[dict]:
        return [
            p for p in pool
            if p["playerID"] != target["playerID"]
            and p["group"] == target["group"]
            and p["totals"].get("minutes", 0.0) >= threshold
            and (not other_competitions_only or p["competitionID"] != target["competitionID"])
        ]

    population = candidates(min_minutes)
    if len(population) < 5:
        population = candidates(min_minutes / 2)
    if len(population) < 5:
        population = candidates(0.0)

    if not population:
        return {"similar": [], "populationSize": 0}

    target_vec = [metric_value(m, target["totals"], target["totals"].get("minutes", 0.0)) for m in metrics]
    pop_vecs = [
        [metric_value(m, p["totals"], p["totals"].get("minutes", 0.0)) for m in metrics]
        for p in population
    ]

    all_vecs = pop_vecs + [target_vec]
    means, stds = [], []
    for i in range(len(metrics)):
        column = [v[i] for v in all_vecs]
        mean = sum(column) / len(column)
        variance = sum((x - mean) ** 2 for x in column) / len(column)
        means.append(mean)
        stds.append(max(math.sqrt(variance), 1e-6))

    target_z = [(target_vec[i] - means[i]) / stds[i] for i in range(len(metrics))]

    scored = []
    for p, vec in zip(population, pop_vecs):
        distance = math.sqrt(sum(
            (((vec[i] - means[i]) / stds[i]) - target_z[i]) ** 2 for i in range(len(metrics))
        ))
        normalised = distance / math.sqrt(len(metrics))
        scored.append({"profile": p, "score": 100.0 * math.exp(-normalised)})

    scored.sort(key=lambda item: item["score"], reverse=True)
    return {"similar": scored[:limit], "populationSize": len(population)}


def comparison(target: dict, candidate: dict, pool: list[dict], min_minutes: float = 270.0) -> list[dict]:
    metrics = metrics_for(target["group"])

    def reference(metric: str) -> list[float]:
        values = [
            metric_value(metric, p["totals"], p["totals"].get("minutes", 0.0))
            for p in pool
            if p["group"] == target["group"] and p["totals"].get("minutes", 0.0) >= min_minutes
        ]
        if len(values) < 5:
            values = [
                metric_value(metric, p["totals"], p["totals"].get("minutes", 0.0))
                for p in pool if p["group"] == target["group"]
            ]
        return values

    def percentile(value: float, values: list[float]) -> float:
        if len(values) < 2:
            return 0.5
        return sum(1 for v in values if v <= value) / len(values)

    rows = []
    for metric in metrics:
        reference_values = reference(metric)
        t_val = metric_value(metric, target["totals"], target["totals"].get("minutes", 0.0))
        c_val = metric_value(metric, candidate["totals"], candidate["totals"].get("minutes", 0.0))
        average = sum(reference_values) / len(reference_values) if reference_values else 0.0
        rows.append({
            "metric": metric,
            "targetValue": t_val,
            "candidateValue": c_val,
            "targetNormalized": percentile(t_val, reference_values),
            "candidateNormalized": percentile(c_val, reference_values),
            "populationAverage": average,
        })
    return rows

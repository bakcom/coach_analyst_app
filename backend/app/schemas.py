"""Request models. Field names are camelCase (matching the Swift domain types)
so request/response JSON is symmetric and decodes 1:1 on the client.
"""

from __future__ import annotations

from pydantic import BaseModel


class TotalsModel(BaseModel):
    minutes: float = 0
    goals: float = 0
    xg: float = 0
    shots: float = 0
    assists: float = 0
    keyPasses: float = 0
    passesAttempted: float = 0
    passesCompleted: float = 0
    progressivePasses: float = 0
    finalThirdPasses: float = 0
    carries: float = 0
    progressiveCarries: float = 0
    dribblesCompleted: float = 0
    tacklesWon: float = 0
    interceptions: float = 0
    clearances: float = 0
    ballRecoveries: float = 0
    pressures: float = 0
    touchesInBox: float = 0
    saves: float = 0


class ProfileModel(BaseModel):
    playerID: str
    name: str
    teamName: str
    competitionID: int
    competitionName: str
    group: str
    primaryPosition: str
    totals: TotalsModel


class Selection(BaseModel):
    competitionID: int
    seasonID: int
    name: str | None = None


class BuildPoolRequest(BaseModel):
    selections: list[Selection]


class SimilarRequest(BaseModel):
    profile: ProfileModel
    otherCompetitionsOnly: bool = True
    limit: int = 10


class ComparisonRequest(BaseModel):
    target: ProfileModel
    candidate: ProfileModel

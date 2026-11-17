"""Coach Analyst BFF: StatsBomb ingestion, pooled player stats, position-aware
similarity, head-to-head comparison, post-game and team analytics.

Run:  uvicorn app.main:app --reload --port 8000
Worker (durable pool builds):  python -m app.worker
"""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException

from . import metrics
from .config import AUTO_WARMUP
from .schemas import BuildPoolRequest, ComparisonRequest, SimilarRequest
from .service import ScoutingService
from .statsbomb import StatsBombClient


@asynccontextmanager
async def lifespan(app: FastAPI):
    client = StatsBombClient()
    service = ScoutingService(client)
    app.state.service = service
    if AUTO_WARMUP:
        try:
            service.warmup()
        except Exception:  # noqa: BLE001
            pass
    try:
        yield
    finally:
        await client.aclose()


app = FastAPI(title="Coach Analyst BFF", version="0.2.0", lifespan=lifespan)


def service() -> ScoutingService:
    return app.state.service


@app.get("/health")
async def health() -> dict:
    from .taskqueue import redis_available

    return {"status": "ok", "queue": "redis" if redis_available() else "inline"}


# MARK: - Catalog

@app.get("/competitions")
async def competitions() -> list[dict]:
    return await service().competitions()


@app.get("/competitions/{competition_id}/{season_id}/teams")
async def teams(competition_id: int, season_id: int) -> list[dict]:
    return await service().teams(competition_id, season_id)


@app.get("/competitions/{competition_id}/{season_id}/teams/{team_id}/dataset")
async def dataset(competition_id: int, season_id: int, team_id: int, name: str = "") -> dict:
    return await service().dataset(competition_id, season_id, name or f"{competition_id}/{season_id}", team_id)


# MARK: - Analytics

@app.get("/competitions/{competition_id}/{season_id}/matches/{match_id}/analysis")
async def match_analysis(competition_id: int, season_id: int, match_id: int) -> dict:
    try:
        return await service().match_analysis(competition_id, season_id, match_id)
    except LookupError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error


@app.get("/competitions/{competition_id}/{season_id}/teams/{team_id}/analysis")
async def team_analysis(competition_id: int, season_id: int, team_id: int, name: str = "") -> dict:
    return await service().team_analysis(competition_id, season_id, name or f"{competition_id}/{season_id}", team_id)


# MARK: - Pool

@app.get("/pool")
async def pool() -> list[dict]:
    return service().current_pool()


@app.get("/pool/status")
async def pool_status(jobId: str | None = None) -> dict:
    return service().job_status(jobId)


@app.post("/pool/build")
async def build_pool(request: BuildPoolRequest, force: bool = False) -> dict:
    if not request.selections:
        raise HTTPException(status_code=400, detail="No competitions selected.")
    return service().start_build([s.model_dump() for s in request.selections], force=force)


@app.post("/pool/warmup")
async def pool_warmup() -> list[dict]:
    return service().warmup()


# MARK: - Similarity

@app.post("/players/similar")
async def similar(request: SimilarRequest) -> dict:
    return metrics.similar(
        request.profile.model_dump(),
        service().current_pool(),
        other_competitions_only=request.otherCompetitionsOnly,
        limit=request.limit,
    )


@app.post("/comparison")
async def comparison(request: ComparisonRequest) -> list[dict]:
    return metrics.comparison(
        request.target.model_dump(),
        request.candidate.model_dump(),
        service().current_pool(),
    )

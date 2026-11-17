"""Job functions executed by the RQ worker. These run in a separate process,
so a build survives an API restart and its state lives in Redis.
"""

from __future__ import annotations

import asyncio

from .builder import build_pool_profiles, ensure_competition_profiles
from .config import CACHE_DIR
from .statsbomb import StatsBombClient
from .storage import write_json_atomic

POOL_FILE = CACHE_DIR / "pool.json"


def _current_job():
    try:
        from rq import get_current_job

        return get_current_job()
    except Exception:  # noqa: BLE001
        return None


def _progress(job, fraction: float, message: str) -> None:
    if job is None:
        return
    job.meta["progress"] = fraction
    job.meta["message"] = message
    job.save_meta()


def build_pool_job(selections: list[dict], force: bool = False) -> int:
    """Builds the pooled player list and writes it to disk."""
    job = _current_job()

    async def run() -> list[dict]:
        client = StatsBombClient()
        try:
            return await build_pool_profiles(
                client,
                selections,
                force=force,
                progress=lambda fraction, message: _progress(job, fraction, message),
            )
        finally:
            await client.aclose()

    profiles = asyncio.run(run())
    write_json_atomic(POOL_FILE, profiles)

    if job is not None:
        job.meta["playerCount"] = len(profiles)
        job.meta["progress"] = 1.0
        job.meta["message"] = f"Pool ready · {len(profiles)} players"
        job.save_meta()
    return len(profiles)


def warm_competitions_job(selections: list[dict]) -> int:
    """Precomputes per-competition caches without touching the pool."""
    job = _current_job()

    async def run() -> int:
        client = StatsBombClient()
        count = max(len(selections), 1)
        try:
            for index, selection in enumerate(selections):
                def report(fraction: float, index: int = index) -> None:
                    _progress(job, (index + fraction) / count, f"Warming {selection.get('name', '')}")
                await ensure_competition_profiles(
                    client,
                    selection["competitionID"],
                    selection["seasonID"],
                    selection.get("name") or "",
                    force=False,
                    progress=report,
                )
        finally:
            await client.aclose()
        return len(selections)

    return asyncio.run(run())

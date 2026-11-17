"""Async client for the StatsBomb open-data repository.

No API key is required. Swapping to the authenticated StatsBomb API is a matter
of changing BASE and adding an auth header.
"""

from __future__ import annotations

import asyncio
import json

import httpx

from .config import CACHE_DIR

BASE = "https://raw.githubusercontent.com/statsbomb/open-data/master/data/"


class StatsBombClient:
    def __init__(self, concurrency: int = 8, cache: bool = True) -> None:
        self._sem = asyncio.Semaphore(concurrency)
        self._cache = cache
        self._client = httpx.AsyncClient(timeout=60.0, follow_redirects=True)
        if cache:
            CACHE_DIR.mkdir(parents=True, exist_ok=True)

    async def aclose(self) -> None:
        await self._client.aclose()

    async def _get(self, path: str):
        cached = CACHE_DIR / path.replace("/", "__")
        if self._cache and cached.exists():
            return json.loads(cached.read_text())

        async with self._sem:
            resp = await self._client.get(BASE + path)
            resp.raise_for_status()
            data = resp.json()

        if self._cache:
            cached.write_text(json.dumps(data))
        return data

    async def competitions(self) -> list[dict]:
        return await self._get("competitions.json")

    async def matches(self, competition_id: int, season_id: int) -> list[dict]:
        return await self._get(f"matches/{competition_id}/{season_id}.json")

    async def lineups(self, match_id: int) -> list[dict]:
        return await self._get(f"lineups/{match_id}.json")

    async def events(self, match_id: int) -> list[dict]:
        return await self._get(f"events/{match_id}.json")

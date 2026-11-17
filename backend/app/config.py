"""Central configuration, read from the environment with sensible defaults."""

from __future__ import annotations

import os
from pathlib import Path


def _flag(name: str) -> bool:
    return os.environ.get(name, "0").lower() in {"1", "true", "yes", "on"}


# Where StatsBomb JSON and aggregated caches are stored.
CACHE_DIR = Path(
    os.environ.get("COACH_CACHE_DIR")
    or os.environ.get("SB_CACHE_DIR")
    or (Path.home() / ".cache" / "coachanalyst-statsbomb")
)

# Durable job queue.
REDIS_URL = os.environ.get("REDIS_URL", "redis://127.0.0.1:6379/0")
QUEUE_NAME = os.environ.get("QUEUE_NAME", "coachanalyst")

# Cap on matches analysed per competition season (keeps the prototype snappy).
MAX_MATCHES_PER_COMPETITION = int(os.environ.get("MAX_MATCHES_PER_COMPETITION", "24"))

# Warm the popular-league caches on startup.
AUTO_WARMUP = _flag("AUTO_WARMUP")

# Widely-followed open-data competition seasons used for warm-up.
POPULAR_LEAGUES = [
    {"competitionID": 11, "seasonID": 90, "name": "La Liga · 2020/2021"},
    {"competitionID": 2, "seasonID": 27, "name": "Premier League · 2015/2016"},
    {"competitionID": 9, "seasonID": 281, "name": "1. Bundesliga · 2023/2024"},
    {"competitionID": 44, "seasonID": 107, "name": "Major League Soccer · 2023"},
    {"competitionID": 72, "seasonID": 30, "name": "FIFA Women's World Cup · 2019"},
]

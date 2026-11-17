"""Redis/RQ wiring for the durable pool-build queue.

Named `taskqueue` (not `queue`) so it never shadows the standard library.
"""

from __future__ import annotations

import redis

from .config import QUEUE_NAME, REDIS_URL

_client: "redis.Redis | None" = None


def redis_client() -> "redis.Redis":
    """A process-wide Redis client (connection pooling is handled by redis-py)."""
    global _client
    if _client is None:
        _client = redis.from_url(REDIS_URL)
    return _client


def redis_available() -> bool:
    try:
        redis_client().ping()
        return True
    except Exception:  # noqa: BLE001
        return False


def pool_queue():
    from rq import Queue

    return Queue(QUEUE_NAME, connection=redis_client())

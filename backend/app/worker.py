"""RQ worker entrypoint.

Uses SimpleWorker (no fork) — forking crashes on macOS once ObjC/network
frameworks have initialised.

Run:  ./.venv/bin/python -m app.worker
"""

from __future__ import annotations

from rq.worker import SimpleWorker

from .config import QUEUE_NAME
from .taskqueue import redis_client


def main() -> None:
    worker = SimpleWorker([QUEUE_NAME], connection=redis_client())
    worker.work(with_scheduler=False)


if __name__ == "__main__":
    main()

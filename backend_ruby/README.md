# Coach Analyst BFF — Ruby on Rails port

A line-for-line port of the FastAPI backend in [`../backend`](../backend), built
as a **Rails 7.1 API-only** app. It exists for **testing and cross-checking** the
Python implementation: it speaks the same HTTP contract and computes the same
analytics, so responses can be diffed directly.

It deliberately shares the Python backend's on-disk cache directory and Redis
queue name, so both backends read the same StatsBomb JSON and pooled players.

```
HTTP contract                          backend/app/*.py          app/services/coach_analyst/*.rb
─────────────────────────────────────  ────────────────────────  ────────────────────────────────
GET  /health                           main.py + taskqueue.py    HealthController + TaskQueue
GET  /competitions                     service.py                CompetitionsController + Service
GET  /competitions/:c/:s/teams         service.py                CompetitionsController + Service
GET  /competitions/:c/:s/teams/:t/dataset   service.py           CompetitionsController + Service
GET  /competitions/:c/:s/matches/:m/analysis service.py + analysis.py  CompetitionsController + Analysis
GET  /competitions/:c/:s/teams/:t/analysis   service.py + analysis.py  CompetitionsController + Analysis
GET  /pool                             service.py                PoolController + Service
GET  /pool/status                      service.py                PoolController + Service
POST /pool/build                       service.py + jobs.py      PoolController + Jobs
POST /pool/warmup                      service.py + jobs.py      PoolController + Jobs
POST /players/similar                  metrics.py                PlayersController + Metrics
POST /comparison                       metrics.py                ComparisonController + Metrics
```

## Layout

```
app/services/coach_analyst/
  config.rb            env-driven settings            (config.py)
  storage.rb           atomic JSON persistence        (storage.py)
  stats_bomb_client.rb open-data client               (statsbomb.py)
  aggregate.rb         event → per-player counters    (aggregate.py)
  metrics.rb           similarity + comparison        (metrics.py)
  builder.rb           incremental disk-cache builds  (builder.py)
  analysis.rb          post-game + season analytics   (analysis.py)
  service.rb           catalog / datasets / jobs      (service.py)
  jobs.rb              queued job functions           (jobs.py)
  task_queue.rb        Redis queue wiring             (taskqueue.py)
  util.rb              Python-compatible primitives
app/controllers/       thin HTTP layer mirroring main.py
config/routes.rb       route table mirroring main.py
parity/                cross-language parity harness
test/                  port of backend/tests
```

## Run

Requires Ruby 3.3 and Redis (optional — enables the durable queue).

```bash
cd backend_ruby
bundle install
cp .env.example .env            # optional

# API
bin/rails server -p 8000
# Durable pool-build worker (separate terminal; requires Redis)
bin/worker                      # or: bin/rails jobs:work
```

The endpoint set and payload shapes match the FastAPI service exactly, including
the `{"detail": "..."}` error body and the 400/404 status codes.

## Tests

The ported pure-function tests hold both backends to the same expectations:

```bash
bin/rails test
```

## Parity harness

`parity/` feeds byte-identical synthetic fixtures (lineups, events, player
pools) to **both** implementations and deep-compares every computed value
(contributions, match stats, shots, momentum, player ratings, season
aggregation, similarity, comparison, pool merge, position grouping):

```bash
bin/rails parity:run
# => PARITY OK — python and ruby agree on all computed values.
```

The harness shells out to `python3` (importing `../backend/app`) and computes
the Ruby side in-process, then diffs JSON with a float tolerance. Exit status is
non-zero on any mismatch, so it can gate CI.

## Fidelity notes

- **Rounding**: Python's `round()` uses banker's rounding on the exact binary
  value; Ruby rounds half away from zero. `CoachAnalyst::Util.py_round`
  reproduces CPython's behaviour (including `round(x)` → `Integer`).
- **Sorts**: Python's `list.sort` is stable; Ruby's `sort_by` is not.
  `Util.stable_sort` restores stability, and `Util.max_key` picks the first key
  on ties, matching `max(dict, key=…)`.
- **Integer division**: Python 3 `/` is true division; the port forces float
  division everywhere the Python code divides.
- **Concurrency**: `asyncio.gather` + a semaphore are replaced with a small
  thread pool (`CHUNK = 6`) plus a `Semaphore` in the HTTP client.
- **Queue**: RQ is replaced by a small Redis list/hash queue
  (`TaskQueue`) with the same meta fields (`status`, `progress`, `message`,
  `playerCount`) and in-process thread fallback when Redis is unavailable.

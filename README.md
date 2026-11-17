# Coach Analyst

A football (soccer) analytics app for coaches. A native iOS client (SwiftUI) for
match, player and team analysis, backed by a FastAPI "BFF" that ingests
**StatsBomb open data** and computes on-device/server analytics.

## Screens

- **Login** → **Dashboard** (own team summary) · **Squad** · **Matches** · **Scouting** · **Profile**
- **Scouting**: competitions → clubs → players → player profile → similar players (position-aware) → head-to-head radar comparison
- **Matches**: your team's fixtures → **Post-Game report** (team stats, xG momentum, shot map, top performers)
- **Team analysis**: style radar, key metrics, recent form and top players — for your team or an opponent

## Architecture

```
iOS app (SwiftUI, @Observable)
  ScoutingStore ──► ScoutingBackend (protocol)
                       ├── LocalScoutingBackend   on-device: StatsBombParsing + SimilarityEngine
                       └── RemoteScoutingBackend  HTTP ──► FastAPI BFF
```

The UI depends only on the `ScoutingBackend` protocol, so the data source is
swappable (on-device vs BFF) without touching screens.

```
backend/ (FastAPI)
  main.py        HTTP API
  service.py     catalog, datasets, analytics, job control
  builder.py     shared, stateless build logic (incremental disk cache)
  aggregate.py   event → per-player counters
  metrics.py     position-aware similarity + comparison
  analysis.py    post-game (match) + team season analytics
  jobs.py        RQ job functions        worker.py  RQ worker entrypoint
  taskqueue.py   Redis/RQ wiring         statsbomb.py  open-data client
  config.py      env-driven settings     storage.py  atomic JSON persistence
  tests/         pure-function tests
```

**Pool builds are durable**: `POST /pool/build` enqueues an RQ job on Redis, run
by a separate worker process, so a build survives an API restart. If Redis is
unavailable the API falls back to an in-process job. Per-competition aggregates
are cached on disk, so builds are incremental.

## Prerequisites

- macOS with **Xcode 16+** and **XcodeGen** (`brew install xcodegen`)
- Python 3.12
- **Redis** (`brew install redis`) — optional; enables the durable queue

## Run the backend

```bash
cd backend
python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt
cp .env.example .env            # optional

# API
./.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
# Durable pool-build worker (separate terminal; requires Redis)
./.venv/bin/python -m app.worker
```

Key endpoints: `GET /health`, `GET /competitions`,
`GET /competitions/{c}/{s}/teams`, `GET /competitions/{c}/{s}/teams/{t}/dataset`,
`GET /competitions/{c}/{s}/matches/{m}/analysis`,
`GET /competitions/{c}/{s}/teams/{t}/analysis`,
`POST /pool/build`, `GET /pool/status`, `POST /pool/warmup`,
`POST /players/similar`, `POST /comparison`.

## Run the app

```bash
xcodegen generate                     # creates CoachAnalyst.xcodeproj
open CoachAnalyst.xcodeproj           # run on an iPhone simulator (iOS 17+)
```

By default the app computes on-device from StatsBomb open data. To use the BFF,
set its URL in **Profile → Data Backend** (applies on next launch) or launch with
`COACH_BACKEND_URL=http://127.0.0.1:8000`.

## Tests

```bash
cd backend && ./.venv/bin/python -m pytest -q
```

## Notes & limitations

- Analytics (post-game, team reports) are server-side; the on-device backend
  returns a clear "needs the BFF backend" error for those screens.
- Only the StatsBomb integration is implemented; Wyscout (CSV) and SkillCorner
  (physical) plug in behind the same `ScoutingBackend` seam.
- Sign-in is a prototype stub (any credentials); swap `AuthStore.signIn` for
  real auth without touching the UI.
- Player/team identity resolution across providers is a planned next step.

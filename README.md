# NovaControl v1.1.0

![Build](https://github.com/kochj23/NovaControl/actions/workflows/build.yml/badge.svg)
![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Port](https://img.shields.io/badge/API-port%2037400-orange)
![Version](https://img.shields.io/badge/version-1.1.0-purple)

**A macOS menu bar app that consolidates the APIs of five apps into one — plus workflow automation, health monitoring, and a full OpenAPI spec.**

NovaControl reads each app's data files directly and exposes a unified HTTP API on `localhost:37400`. Stop running OneOnOne, NMAPScanner, RsyncGUI, TopGUI, and News Summary just to give your AI assistant API access.

---

## What It Replaces

| App | Old Port | NovaControl Route |
|-----|----------|-------------------|
| OneOnOne | 37421 | `/api/oneonone/*` |
| NMAPScanner | 37423 | `/api/nmap/*` |
| RsyncGUI | 37424 | `/api/rsync/*` |
| TopGUI | 37443 | `/api/system/*` |
| News Summary | 37438 | `/api/news/*` |

---

## What's New in v1.1.0 (April 2026)

### Health Dashboard · Workflow Automation · OpenAPI Docs · ETag Caching

**Health Dashboard tab** — Traffic light status for every service, live CPU/RAM/disk pressure indicators, and an "Attention Required" section surfacing open action items, cron errors, and active threats.

**Workflow Automation Engine** — State machine that routes data between apps automatically. Three built-in workflows:
- **New Action Item → Slack Alert** — posts high-priority items to `#nova-chat`
- **Completed Action Item → Jira Ticket** — creates follow-up tickets via JiraSummary API
- **Daily Open Actions Summary Email** — sends digest via `nova_herd_mail.sh`

**OpenAPI 3.0 docs** — `GET /api/docs` returns a machine-readable spec for all 28 endpoints. Ready for Swagger UI, Postman, or any OpenAPI toolchain.

**Content graph** — `GET /api/graph` returns a live node/edge graph of service relationships. Neo4j-ready: connect `bolt://localhost:7687` and POST `/api/graph/ingest` for full graph queries.

**Prometheus metrics** — `GET /metrics` returns 16 gauges in standard text format: CPU, RAM, disk I/O, uptime, device counts, threat counts, goal stats, and Nova cron error count. Drop straight into Grafana.

**ETag caching** — All GET responses include an `ETag` header. Send `If-None-Match` to get `304 Not Modified` when data is unchanged (uses stable sorted-key JSON serialization).

**Manual health notes** — `POST /api/health/status` stores context ("Running ML models today", memory pressure level) that flows into health correlation on the goals and healthcheck endpoints.

---

## API

All routes on `http://127.0.0.1:37400` (loopback only). Complete spec at `/api/docs`.

```bash
# Status & health
curl http://127.0.0.1:37400/api/status
curl http://127.0.0.1:37400/api/health
curl http://127.0.0.1:37400/api/docs

# ETag caching
ETAG=$(curl -sI http://127.0.0.1:37400/api/status | grep -i etag | awk '{print $2}')
curl http://127.0.0.1:37400/api/status -H "If-None-Match: $ETAG"  # → 304

# Prometheus metrics
curl http://127.0.0.1:37400/metrics

# OneOnOne
curl http://127.0.0.1:37400/api/oneonone/meetings
curl http://127.0.0.1:37400/api/oneonone/actionitems
curl http://127.0.0.1:37400/api/oneonone/people
curl http://127.0.0.1:37400/api/oneonone/goals
curl http://127.0.0.1:37400/api/oneonone/goals/insights

# NMAPScanner
curl http://127.0.0.1:37400/api/nmap/devices
curl http://127.0.0.1:37400/api/nmap/threats
curl -X POST http://127.0.0.1:37400/api/nmap/scan -d '{"ip":"192.168.1.0/24"}'

# RsyncGUI
curl http://127.0.0.1:37400/api/rsync/jobs
curl http://127.0.0.1:37400/api/rsync/history
curl -X POST http://127.0.0.1:37400/api/rsync/jobs/{id}/run

# System stats
curl http://127.0.0.1:37400/api/system/stats
curl http://127.0.0.1:37400/api/system/processes

# News
curl http://127.0.0.1:37400/api/news/breaking
curl http://127.0.0.1:37400/api/news/articles/{category}

# Nova AI
curl http://127.0.0.1:37400/api/nova/status
curl http://127.0.0.1:37400/api/nova/memory
curl http://127.0.0.1:37400/api/nova/crons
curl http://127.0.0.1:37400/api/ai/status

# Topology & graph
curl http://127.0.0.1:37400/api/topology
curl http://127.0.0.1:37400/api/graph

# Manual health note
curl -X POST http://127.0.0.1:37400/api/health/status \
  -H "Content-Type: application/json" \
  -d '{"memoryPressure":"high","notes":"Running ML models today"}'

# Workflow automation
curl http://127.0.0.1:37400/api/workflows
curl -X POST http://127.0.0.1:37400/api/workflows/action-item-to-slack/run \
  -H "Content-Type: application/json" \
  -d '{"title":"Deploy v2.0","assignee":"Jordan"}'
curl http://127.0.0.1:37400/api/workflows/runs
```

---

## How It Works

NovaControl reads each app's data files directly — no app needs to be running:

- **OneOnOne** → `~/Library/Application Support/OneOnOne/*.json` *(CloudKit-synced — open OneOnOne once to populate local cache)*
- **NMAPScanner** → `~/Library/Containers/com.digitalnoise.nmapscanner.macos/.../Preferences/*.plist`
- **RsyncGUI** → `~/Library/Application Support/RsyncGUI/jobs.json`
- **TopGUI** → Live system stats via `host_statistics` + `ps` (no files needed)
- **News Summary** → `~/Library/Application Support/NewsSummary/*.json`

Data refreshes every 60 seconds automatically.

---

## Installation

### Requirements
- macOS 14.0+
- Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

### Build

```bash
git clone https://github.com/kochj23/NovaControl
cd NovaControl
xcodegen generate
xcodebuild -scheme NovaControl -configuration Release build -allowProvisioningUpdates
```

Or open `NovaControl.xcodeproj` in Xcode and build normally.

### First Run

On first launch, macOS will ask **"NovaControl would like to access data from other apps."** — click **Allow**. This is required to read NMAPScanner's sandboxed preferences. Grant it permanently in System Settings → Privacy & Security → Automation.

---

## Security

- API binds to `127.0.0.1` only — never exposed to the network
- Read-only access to all app data files
- No credentials stored or transmitted
- See [SECURITY.md](SECURITY.md) for vulnerability reporting

---

## Architecture

```
NovaControl/
├── NovaControlApp.swift          # App entry, menu bar setup
├── Models/
│   └── ServiceModels.swift       # Codable models for all services
├── Services/
│   ├── DataManager.swift         # ObservableObject, 60s auto-refresh
│   ├── NovaAPIServer.swift       # NWListener HTTP server, port 37400
│   └── Readers/
│       ├── OneOnOneReader.swift
│       ├── NMAPReader.swift
│       ├── RsyncReader.swift
│       ├── SystemStatsReader.swift
│       └── NewsSummaryReader.swift
├── Services/
│   ├── WorkflowEngine.swift      # State machine: Slack/Jira/email steps
│   └── Readers/
│       ├── NovaReader.swift
│       └── MLXCodeReader.swift
└── Views/
    └── StatusWindowView.swift    # 6-tab SwiftUI window (incl. Health)
```

## Workflow Automation

Workflows are stored in `~/Library/Application Support/NovaControl/Workflows/definitions.json` and persist across launches.

Each workflow has:
- **trigger** — `newActionItem(priority:)`, `actionItemCompleted`, or `manual`
- **steps** — ordered list of `postToSlack`, `createJiraTicket`, `sendEmail`, `webhook`, or `wait`
- **continueOnFailure** — whether to proceed past a failed step

```bash
# Run a workflow manually with context variables
curl -X POST http://127.0.0.1:37400/api/workflows/daily-action-summary-email/run \
  -H "Content-Type: application/json" \
  -d '{"count":"5","date":"2026-04-03"}'

# Check recent runs
curl http://127.0.0.1:37400/api/workflows/runs
```

To add `{{OWNER_EMAIL}}` to the email workflow, set the `to` field in the workflow step config to your actual address after cloning.

---

## License

MIT License — see [LICENSE](LICENSE)

Written by Jordan Koch

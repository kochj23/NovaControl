# NovaControl

![Build](https://github.com/kochj23/NovaControl/actions/workflows/build.yml/badge.svg)
![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)
![API Port](https://img.shields.io/badge/API-port%2037400-purple)
![Version](https://img.shields.io/badge/version-1.3.0-brightgreen)

A macOS menu bar application that consolidates the HTTP APIs of multiple local
applications into a single unified endpoint. NovaControl reads each app's data
files directly, exposes everything on `localhost:37400`, and provides a SwiftUI
dashboard with health monitoring, workflow automation, and Prometheus-compatible
metrics -- all without requiring the source applications to be running.

**v1.3.0 adds Plex media server status, iCal/ICS calendar reading, and a
HealthKit data snapshot endpoint.** All Nova scripts that previously called
port 37421 (OneOnOne) have been migrated to port 37400.

---

## Architecture

```mermaid
graph TB
    subgraph NovaControl
        MB[Menu Bar Icon] --> SW[StatusWindowView<br/>7-Tab Dashboard]
        AD[AppDelegate] --> DM[DataManager<br/>60s auto-refresh]
        AD --> API[NovaAPIServer<br/>NWListener :37400<br/>44+ routes / ETag / OpenAPI]
        DM --> WE[WorkflowEngine<br/>Slack / Jira / Email / Webhook]
    end

    subgraph Readers
        DM --> OOR[OneOnOneReader]
        DM --> NR[NMAPReader]
        DM --> RR[RsyncReader]
        DM --> SSR[SystemStatsReader]
        DM --> NSR[NewsSummaryReader]
        DM --> NVR[NovaReader]
        DM --> MLR[MLXCodeReader]
        DM --> HKR[HomeKitReader]
        DM --> AIR[AIServiceReader]
        DM --> BBR[BigBrotherReader<br/>15s refresh]
        DM --> PLR[PlexReader ★ new]
        DM --> CAL[CalendarReader ★ new]
        DM --> HLR[HealthKitReader ★ new]
    end

    subgraph Data Sources
        OOR -->|JSON files| OOD[~/Library/App Support/OneOnOne/]
        NR -->|Plist| NMD[NMAPScanner Container]
        RR -->|JSON files| RSD[~/Library/App Support/RsyncGUI/]
        SSR -->|Mach/IOKit| SYS[Kernel APIs]
        NSR -->|JSON files| NSD[~/Library/App Support/NewsSummary/]
        NVR -->|HTTP + CLI| GW[OpenClaw :18789]
        NVR -->|HTTP| MEM[Memory Server :18790]
        NVR -->|HTTP| OLL[Ollama :11434]
        MLR -->|HTTP proxy| MLXC[MLXCode :37422]
        HKR -->|Shortcuts CLI| HK[HomeKit Scenes]
        AIR -->|HTTP| OLL
        PLR -->|HTTP + token| PLEX[Synology Plex :32400]
        CAL -->|ICS URL from Keychain| ICAL[iCal / CalDAV Feed]
        HLR -->|JSON fallback| HDF[~/.openclaw/private/health/latest.json]
    end

    subgraph API Routes
        API --> R1[/api/oneonone/*]
        API --> R2[/api/nmap/*]
        API --> R3[/api/rsync/*]
        API --> R4[/api/system/*]
        API --> R5[/api/nova/* /api/ai/*]
        API --> R6[/api/health /metrics /api/docs]
        API --> R7[/api/workflows /api/topology /api/graph]
        API --> R8[/api/homekit/*]
        API --> R9[/api/bigbrother/* → proxy :37461]
        API --> R10[/api/plex/* ★ new]
        API --> R11[/api/calendar/* ★ new]
        API --> R12[/api/health/snapshot ★ new]
    end

    style MB fill:#5535ff,color:#fff
    style API fill:#2a6,color:#fff
    style DM fill:#38d,color:#fff
    style WE fill:#c55,color:#fff
    style BBR fill:#a35,color:#fff
    style PLR fill:#e6a817,color:#000
    style CAL fill:#e6a817,color:#000
    style HLR fill:#e6a817,color:#000
```

### Data Flow

NovaControl never requires the source applications to be running. It reads
their persisted data files on disk and supplements that with live system
metrics from kernel APIs. The data path for each service:

| Service | Data Source | Refresh |
|---------|-----------|---------|
| OneOnOne | `~/Library/Application Support/OneOnOne/*.json` (CloudKit-synced) | 60s |
| NMAPScanner | `~/Library/Containers/com.digitalnoise.nmapscanner.macos/.../Preferences/*.plist` | 60s |
| RsyncGUI | `~/Library/Application Support/RsyncGUI/jobs.json` + `History/history.json` | 60s |
| System Stats | Mach `host_statistics` / `vm_statistics64` / IOKit disk I/O / `sysctl kern.boottime` | 60s |
| News Summary | `~/Library/Application Support/NewsSummary/*.json` | 60s |
| Nova Gateway | HTTP probe `127.0.0.1:18789/health` | 60s |
| Nova Memory | HTTP probe `127.0.0.1:18790/health` + `/stats` | 60s |
| Ollama | HTTP `127.0.0.1:11434/api/tags` + `/api/ps` + `/api/generate` | 60s / on-demand |
| MLX Server | HTTP `127.0.0.1:5050/v1/models` | 60s |
| MLXCode | HTTP proxy `127.0.0.1:37422` | 60s |
| HomeKit | Shortcuts CLI (`/usr/bin/shortcuts run`) | 5-min cache |
| AI Summarization | Ollama `/api/generate` (nova:latest model) | on-demand |
| Big Brother | HTTP `127.0.0.1:37461/bb/*` (diagnostics daemon) | 15s |
| Plex | HTTP `192.168.1.10:32400` — token loaded from macOS Keychain | on-demand |
| Calendar | ICS URL loaded from macOS Keychain → parsed locally | on-demand |
| HealthKit | `~/.openclaw/private/health/latest.json` (iOS export fallback) | on-demand |

---

## What It Replaces

NovaControl consolidates multiple separate app APIs and data sources into one
port. The original apps no longer need to run just to give an AI assistant
API access to their data.

| App / Service | Original Port | NovaControl Route Prefix |
|---------------|---------------|--------------------------|
| OneOnOne | 37421 | `/api/oneonone/*` |
| HomeKitControl | 37432 | `/api/homekit/*` |
| NMAPScanner | 37423 | `/api/nmap/*` |
| RsyncGUI | 37424 | `/api/rsync/*` |
| TopGUI | 37443 | `/api/system/*` |
| News Summary | 37438 | `/api/news/*` |
| Plex Media Server | external | `/api/plex/*` |
| iCal / CalDAV | external | `/api/calendar/*` |
| HealthKit / iOS export | local file | `/api/health/snapshot` |

Additional routes exist for Nova/OpenClaw AI services (`/api/nova/*`,
`/api/ai/*`, `/api/mlxcode/*`), HomeKit scene execution, AI-powered
summarization, health monitoring, workflow automation, topology mapping,
content graphs, and Prometheus metrics export.

All Nova scripts that previously called OneOnOne on port 37421 have been
migrated to port 37400.

---

## Features

### Unified API Gateway (44+ Endpoints)

A single HTTP server on `127.0.0.1:37400` using Apple's Network framework
(`NWListener`). All routes return JSON. Every GET response includes an `ETag`
header computed via SHA-256 over sorted-key JSON serialization, so clients can
send `If-None-Match` and receive `304 Not Modified` when data has not changed.

### Menu Bar Dashboard (7-Tab SwiftUI Window)

A floating status window accessible from the menu bar icon. Tabs:

- **Action Items** -- Open action items from OneOnOne with priority coloring,
  assignee lookup, and due date warnings.
- **Devices** -- Network devices from NMAPScanner with device type icons,
  manufacturer info, and per-host threat counts.
- **System** -- Live CPU, RAM, disk I/O, and uptime badges plus a top-20
  process list.
- **News** -- Unread breaking news from News Summary with source badges,
  category labels, and click-to-open in browser.
- **Nova** -- AI service health grid (OpenClaw, Memory Server, Ollama,
  SwarmUI, ComfyUI, Nova-NextGen), Nova identity stats (model, memories,
  sessions, gateway), and cron job health with error highlighting.
- **Health** -- Overall system banner (operational / degraded / outage),
  per-service traffic lights, local LLM inventory with backend badges
  (Ollama vs MLX), system pressure gauges (CPU, RAM, disk R/W), and an
  "Attention Required" section surfacing open action items, cron errors,
  and active security threats.
- **Diagnostics** -- Big Brother daemon status (uptime, events total, services
  down), per-service health grid with restart counts, and a filterable
  heal-event feed (critical / warning / info) showing what broke and how it
  was fixed. Includes a "Force Check" button to trigger an immediate sweep.

### Health Monitoring

`GET /api/health` runs a comprehensive check across all data sources and
returns per-source pass/fail status. `POST /api/health/status` accepts manual
health notes (memory pressure level + freeform text) that flow into health
correlation on the goals insights endpoint.

### Workflow Automation Engine

A state machine that routes data between apps. Each workflow has a trigger
type, an ordered list of steps, and a `continueOnFailure` flag per step.

Step types: `postToSlack`, `createJiraTicket`, `sendEmail`, `webhook`, `wait`.

Built-in workflows:

| Workflow | Trigger | Steps |
|----------|---------|-------|
| New Action Item to Slack Alert | `newActionItem(priority: "high")` | Post to `#nova-chat` |
| Completed Action Item to Jira Ticket | `actionItemCompleted` | Create Jira issue via JiraSummary API, then notify Slack |
| Daily Open Actions Summary Email | `manual` | Send digest via `nova_herd_mail.sh` |

Workflow definitions persist in
`~/Library/Application Support/NovaControl/Workflows/definitions.json`.

### Prometheus Metrics

`GET /metrics` returns 16 gauges in standard Prometheus text format, ready for
Grafana or any Prometheus-compatible scraper:

```
novacontrol_cpu_percent, novacontrol_cpu_user_percent,
novacontrol_cpu_sys_percent, novacontrol_mem_used_gb,
novacontrol_mem_total_gb, novacontrol_disk_read_mbs,
novacontrol_disk_write_mbs, novacontrol_uptime_seconds,
novacontrol_nmap_devices, novacontrol_nmap_threats,
novacontrol_goals_total, novacontrol_goals_completed,
novacontrol_actions_open, novacontrol_nova_gateway,
novacontrol_nova_memories, novacontrol_nova_cron_errors
```

### OpenAPI 3.0 Documentation

`GET /api/docs` returns a machine-readable OpenAPI 3.0.3 spec covering all
endpoints. Compatible with Swagger UI, Postman, and any OpenAPI toolchain.

### Content Graph

`GET /api/graph` returns a node/edge graph of service relationships built from
live data. Includes service nodes, news category nodes derived from current
articles, and device type nodes from the latest scan. The response includes a
Neo4j connection stub for full graph queries when a Bolt server is available.

### Topology Mapping

`GET /api/topology` returns a live map of inter-service communication links
with active/inactive status based on real endpoint probes. Covers data sync,
device health, AI inference, memory, and notification pathways.

### AI Service Monitoring

`GET /api/ai/status` probes seven local AI services in parallel using
`TaskGroup` and returns per-service health with enriched detail (model counts
from Ollama, backend counts from Nova-NextGen, memory stats from the memory
server).

`GET /api/ai/llms` returns a combined inventory of all local LLMs across
Ollama and MLX backends, including loaded/idle status, model size, parameter
count, quantization level, and family.

### Goal Insights with Health Correlation

`GET /api/oneonone/goals/insights` returns goal completion metrics (total,
rate, status breakdown, recently completed) correlated with current system
health. If CPU is above 80%, memory is above 85%, or a manual critical
pressure note exists, the response includes an advisory note.

---

## API Reference

All routes bind to `http://127.0.0.1:37400` (loopback only). Full OpenAPI
spec available at `GET /api/docs`.

### Status and Health

```bash
curl http://127.0.0.1:37400/api/status
curl http://127.0.0.1:37400/api/health
curl http://127.0.0.1:37400/api/docs
curl http://127.0.0.1:37400/metrics
```

### ETag Caching

```bash
ETAG=$(curl -sI http://127.0.0.1:37400/api/status | grep -i etag | awk '{print $2}')
curl http://127.0.0.1:37400/api/status -H "If-None-Match: $ETAG"  # 304 Not Modified
```

### OneOnOne

```bash
curl http://127.0.0.1:37400/api/oneonone/meetings
curl http://127.0.0.1:37400/api/oneonone/meetings?limit=5
curl http://127.0.0.1:37400/api/oneonone/actionitems
curl http://127.0.0.1:37400/api/oneonone/actionitems?completed=false
curl http://127.0.0.1:37400/api/oneonone/people
curl http://127.0.0.1:37400/api/oneonone/goals
curl http://127.0.0.1:37400/api/oneonone/goals/insights
```

### NMAPScanner

```bash
curl http://127.0.0.1:37400/api/nmap/devices
curl http://127.0.0.1:37400/api/nmap/threats
curl -X POST http://127.0.0.1:37400/api/nmap/scan \
  -H "Content-Type: application/json" \
  -d '{"ip":"192.168.1.0/24"}'
```

### RsyncGUI

```bash
curl http://127.0.0.1:37400/api/rsync/jobs
curl http://127.0.0.1:37400/api/rsync/history
curl -X POST http://127.0.0.1:37400/api/rsync/jobs/{id}/run
```

### System Stats

```bash
curl http://127.0.0.1:37400/api/system/stats
curl http://127.0.0.1:37400/api/system/processes
```

### News

```bash
curl http://127.0.0.1:37400/api/news/breaking
curl http://127.0.0.1:37400/api/news/favorites
curl http://127.0.0.1:37400/api/news/articles/technology
```

### Nova AI

```bash
curl http://127.0.0.1:37400/api/nova/status
curl http://127.0.0.1:37400/api/nova/memory
curl http://127.0.0.1:37400/api/nova/crons
curl http://127.0.0.1:37400/api/ai/status
curl http://127.0.0.1:37400/api/ai/llms
curl http://127.0.0.1:37400/api/mlxcode/status
```

### Topology and Graph

```bash
curl http://127.0.0.1:37400/api/topology
curl http://127.0.0.1:37400/api/graph
```

### Manual Health Note

```bash
curl -X POST http://127.0.0.1:37400/api/health/status \
  -H "Content-Type: application/json" \
  -d '{"memoryPressure":"high","notes":"Running ML training workload"}'

curl http://127.0.0.1:37400/api/health/status
```

### Workflow Automation

```bash
curl http://127.0.0.1:37400/api/workflows

curl -X POST http://127.0.0.1:37400/api/workflows/action-item-to-slack/run \
  -H "Content-Type: application/json" \
  -d '{"title":"Deploy v2.0","assignee":"Jordan"}'

curl -X POST http://127.0.0.1:37400/api/workflows/daily-action-summary-email/run \
  -H "Content-Type: application/json" \
  -d '{"count":"5"}'

curl http://127.0.0.1:37400/api/workflows/runs
```

### Plex

PlexReader connects to the Plex Media Server using a token stored in macOS
Keychain. Server address defaults to `192.168.1.10:32400` (Synology NAS).

```bash
curl http://127.0.0.1:37400/api/plex/status
curl http://127.0.0.1:37400/api/plex/playing
curl http://127.0.0.1:37400/api/plex/ondeck
curl http://127.0.0.1:37400/api/plex/ondeck?limit=5
curl http://127.0.0.1:37400/api/plex/recent
curl http://127.0.0.1:37400/api/plex/recent?limit=20
curl http://127.0.0.1:37400/api/plex/library
```

| Endpoint | Description |
|----------|-------------|
| `/api/plex/status` | Server version, active streams, library summary |
| `/api/plex/playing` | All currently active playback sessions |
| `/api/plex/ondeck` | On-deck items (in-progress; `limit` query param, default 10) |
| `/api/plex/recent` | Recently added items across all libraries (`limit` param, default 10) |
| `/api/plex/library` | Per-library item counts and metadata |

### Calendar

CalendarReader fetches an ICS URL stored in macOS Keychain under the key
`NovaControl.CalendarURL` and parses events locally — no calendar app needs
to be running.

```bash
curl http://127.0.0.1:37400/api/calendar/today
curl http://127.0.0.1:37400/api/calendar/upcoming
curl http://127.0.0.1:37400/api/calendar/upcoming?minutes=60
curl http://127.0.0.1:37400/api/calendar/events
curl http://127.0.0.1:37400/api/calendar/events?days=14
```

| Endpoint | Description |
|----------|-------------|
| `/api/calendar/today` | Today's and tomorrow's events |
| `/api/calendar/upcoming` | Events starting within N minutes (default 30) |
| `/api/calendar/events` | All events in the next N days (default 7) |

### HealthKit

`GET /api/health/snapshot` returns a health data snapshot. Because HealthKit
on macOS requires Mac App Store entitlement approval, this endpoint first
attempts to serve a cached JSON export at
`~/.openclaw/private/health/latest.json` (written by the iPhone Health app
or a HealthKit export tool). If native HealthKit access is available (macOS
13+), it is also attempted and the result is written back to the cache file.

```bash
curl http://127.0.0.1:37400/api/health/snapshot
```

Response includes a `source` field indicating `"cached_ios_export"` or
`"healthkit_native"`. If no data is available, the response is HTTP 404 with
a hint on how to export data from the Health app.

---

## Installation

NovaControl is distributed as a DMG installer. It is not available on the Mac
App Store. The app runs without sandbox restrictions because it needs direct
read access to other applications' data files and containers.

### Requirements

- macOS 14.0 (Sonoma) or later
- For source builds: Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Optional: [nmap](https://nmap.org/) installed via Homebrew for live scan support (`brew install nmap`)

### Install from DMG

1. Open the DMG file.
2. Drag NovaControl to your Applications folder.
3. Launch NovaControl from Applications or Spotlight.
4. On first launch, macOS will prompt for data access permission -- click
   **Allow**. This is required to read NMAPScanner's sandboxed container
   preferences. You can grant this permanently in System Settings > Privacy
   & Security > Automation.

### Build from Source

```bash
git clone git@github.com:kochj23/NovaControl.git
cd NovaControl
xcodegen generate
xcodebuild -scheme NovaControl -configuration Release build -allowProvisioningUpdates
```

Or open `NovaControl.xcodeproj` in Xcode and press Cmd+B.

---

## Project Structure

```
NovaControl/
+-- NovaControlApp.swift              App entry point, NSStatusItem menu bar setup
+-- Models/
|   +-- ServiceModels.swift           Codable models for all service domains
+-- Services/
|   +-- DataManager.swift             @MainActor ObservableObject, 60s timer, async data fetches
|   +-- NovaAPIServer.swift           NWListener HTTP server, 44+ routes, ETag, OpenAPI, Prometheus
|   +-- WorkflowEngine.swift          State machine: triggers, steps, run history, Slack/Jira/email
|   +-- Readers/
|       +-- OneOnOneReader.swift       Reads meetings, action items, people, goals from JSON
|       +-- NMAPReader.swift           Reads devices/threats from sandboxed plist, runs nmap scans
|       +-- RsyncReader.swift          Reads sync jobs and history, can execute rsync
|       +-- SystemStatsReader.swift    Mach host_statistics, vm_statistics64, IOKit disk I/O, ps
|       +-- NewsSummaryReader.swift    Reads articles from JSON, filters by category/favorites
|       +-- NovaReader.swift           Probes OpenClaw gateway/memory, Ollama, MLX, cron parsing
|       +-- MLXCodeReader.swift        Proxies MLXCode HTTP API on port 37422
|       +-- PlexReader.swift           Plex Media Server: status, now playing, on deck, recent, library
|       +-- CalendarReader.swift       ICS/CalDAV feed parser: today, upcoming, events by date range
|       +-- HealthKitReader.swift      HealthKit snapshot; falls back to ~/.openclaw/private/health/
+-- Views/
|   +-- StatusWindowView.swift         7-tab SwiftUI dashboard
+-- Resources/
    +-- NovaControl.entitlements       No sandbox, network server + client entitlements
```

### Key Technical Details

- **HTTP Server**: Built on Apple's Network framework (`NWListener` + `NWConnection`)
  rather than a third-party web server. Zero external dependencies for the
  server layer.
- **Concurrency**: All readers are Swift `actor` types. `DataManager` uses
  structured concurrency (`async let`) to fetch all 16 data streams in
  parallel on each 60-second refresh cycle.
- **ETag Implementation**: SHA-256 hash over `JSONSerialization` output with
  `.sortedKeys` option. Identical data always produces the same hash,
  regardless of dictionary ordering.
- **Disk I/O Metrics**: Delta-based calculation using IOKit
  `IOBlockStorageDriver` statistics. The reader stores a previous sample and
  computes MB/s from the byte delta divided by elapsed time.
- **Memory Stats**: Uses Mach `vm_statistics64` for active, wired, compressor,
  free, and inactive page counts, multiplied by `vm_page_size`.
- **No External Dependencies**: The only framework dependency beyond Foundation
  and SwiftUI is `IOKit.framework` (linked via `project.yml`). No
  CocoaPods, SPM packages, or Carthage dependencies.
- **Build System**: XcodeGen (`project.yml`) generates the `.xcodeproj`.
  Bundle ID: `net.digitalnoise.NovaControl`.

---

## Security

NovaControl is designed for local-only operation. It is not a network service.

- **Loopback binding**: The HTTP server binds exclusively to `127.0.0.1`.
  It is never exposed to the local network or the internet.
- **Read-only data access**: All readers only read app data files. NovaControl
  never writes to another application's data store.
- **Credentials in macOS Keychain**: All tokens and URLs that require
  credentials are stored in macOS Keychain and loaded at runtime via the
  Security framework. This includes the Plex token (`NovaControl.PlexToken`),
  the Calendar ICS URL (`NovaControl.CalendarURL`), and the Slack token for
  workflow automation (read from `~/.openclaw/openclaw.json`). Nothing is
  hardcoded or stored in UserDefaults.
- **No outbound network requests** (except workflows): The core data
  collection is entirely local. Outbound HTTP calls only occur when a
  workflow step explicitly sends to Slack, Jira, or a webhook.
- **No sandbox**: The app requires unrestricted file system access to read
  data from other applications' containers and Application Support
  directories. The entitlements file disables the app sandbox and enables
  network server + client capabilities.

For vulnerability reporting, see [SECURITY.md](SECURITY.md).

---

## Configuration

NovaControl works out of the box with no configuration. It automatically
discovers data files from the standard Application Support and container
locations for each source app.

### Workflow Customization

Workflow definitions are stored in:

```
~/Library/Application Support/NovaControl/Workflows/definitions.json
```

Each workflow consists of:

- **trigger** -- `newActionItem(priority:)`, `actionItemCompleted`, or `manual`
- **steps** -- Ordered list of step types with configuration maps
- **continueOnFailure** -- Per-step flag controlling whether the engine
  proceeds past a failed step

Template variables in step configs use `{{key}}` syntax. The engine
automatically fills `{{date}}` with today's date. Additional context variables
can be passed via the POST body when running a workflow manually.

### Prometheus / Grafana

Point your Prometheus scrape config at `http://127.0.0.1:37400/metrics`.
All 16 gauges use the `novacontrol_` prefix for easy dashboarding.

### Neo4j Integration

The content graph endpoint (`/api/graph`) returns an in-memory graph by
default. To enable full graph queries, run Neo4j on `bolt://localhost:7687`
and POST to `/api/graph/ingest` to populate the database.

---

## Changelog

### v1.3.0 (May 2026)

- **PlexReader** — five new endpoints for Plex Media Server integration:
  status, now playing, on deck, recently added, and per-library summary.
  Plex token loaded from macOS Keychain at runtime.
- **CalendarReader** — three new calendar endpoints: today/tomorrow events,
  upcoming events within N minutes, and events across a date range. ICS URL
  loaded from macOS Keychain; parsed entirely locally with no calendar app
  dependency.
- **HealthKitReader** — `/api/health/snapshot` endpoint serving iOS HealthKit
  export data from `~/.openclaw/private/health/latest.json`; falls through
  to native HealthKit on macOS 13+ if the entitlement is available.
- All Nova scripts migrated from OneOnOne port 37421 to NovaControl port 37400.
- Route count updated from 28 to 44+.

### v1.1.0 (April 2026)

- Health Dashboard tab with traffic light indicators, system pressure gauges,
  local LLM inventory, and "Attention Required" section
- Workflow Automation Engine with Slack, Jira, email, and webhook step types
- OpenAPI 3.0 documentation at `/api/docs`
- Prometheus metrics export at `/metrics` (16 gauges)
- Content graph endpoint at `/api/graph` with Neo4j integration stub
- ETag caching on all GET responses via SHA-256 sorted-key hashing
- Manual health note endpoint (`POST /api/health/status`)
- Goal insights with health correlation (`/api/oneonone/goals/insights`)
- AI service monitoring with parallel probes for 7 services
- Local LLM inventory across Ollama and MLX backends
- Topology mapping of inter-service communication links
- MLXCode API proxy routes

### v1.0.0 (March 2026)

- Initial release
- Unified API gateway on port 37400 replacing 5 separate app APIs
- Menu bar app with 5-tab SwiftUI dashboard
- OneOnOne, NMAPScanner, RsyncGUI, TopGUI, and News Summary readers
- 60-second auto-refresh cycle
- Nova/OpenClaw gateway and memory server probes

---

## Testing

NovaControl includes 45 unit tests across three test suites covering all Codable models, workflow automation types, and security compliance.

### Test Suites

| Suite | Tests | Coverage |
|---|---|---|
| `ServiceModelsTests` | 26 | All 15+ model types: ServiceInfo, Meeting, ActionItem, Person, Goal, ScannedDevice, ThreatFinding, SyncJob, ExecutionHistoryEntry, NewsArticle, NovaCronJob, NovaStatus, AIService, LocalLLM, TopologyConnection, ManualHealthInput, NewsCategory. Codable round-trip tests for ActionItem, SyncJob, NewsArticle. |
| `WorkflowEngineTests` | 10 | WorkflowDefinition codable round-trip, all 3 trigger types (manual, newActionItem, actionItemCompleted), all 5 step types (postToSlack, createJiraTicket, sendEmail, webhook, wait), WorkflowRun status enum, multi-step workflow serialization. |
| `SecurityTests` | 9 | Credential scan across all Swift source files (sk-, AKIA, ghp_, xoxb-, xoxp-), personal email detection, entitlements validation (sandbox disabled, network server/client), Slack token config loading, IP address audit (loopback-only), template injection prevention. |

### Run Tests

```bash
cd NovaControl
xcodegen generate
xcodebuild test -scheme NovaControl -destination 'platform=macOS'
```

### Security Test Coverage

- All `.swift` files scanned for 5 hardcoded credential patterns
- Personal email addresses verified absent from source
- IP addresses verified as `127.0.0.1` only (loopback binding)
- Entitlements confirmed: sandbox disabled, network server + client enabled
- Slack token confirmed loaded from `~/.openclaw/openclaw.json`
- Workflow template syntax verified free of shell metacharacters

---

## License

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

MIT License -- see [LICENSE](LICENSE) for the full text.

Copyright (c) 2026 Jordan Koch

---

Written by Jordan Koch

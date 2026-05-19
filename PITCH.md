# NovaControl

**The unified API gateway for your local AI infrastructure.**

---

## The Problem

You have a dozen local services. An AI assistant. Network storage. HomeKit devices. Monitoring scripts. Media servers. Each one speaks its own protocol, lives on its own port, and requires its own process to be running.

Your AI asks "what's happening on my network?" and the answer requires hitting five different endpoints, parsing three file formats, and hoping every service is still alive.

This doesn't scale. It breaks at 3am. It's unmanageable.

## The Solution

NovaControl is a macOS menu bar application that consolidates everything into a single REST API on port 37400. It reads data files directly from disk, probes live services, monitors hardware health, and exposes it all through 44+ documented routes with ETag caching and OpenAPI specs.

The source applications don't need to be running. NovaControl reads their persisted state and makes it available on demand.

One port. One process. Every answer.

---

## What It Does

### Unified API Gateway (port 37400)

Every Nova component — the brain, the scheduler, the display, the health system — talks to NovaControl. It's the single source of truth for the entire ecosystem.

- **44+ REST API routes** with consistent JSON responses
- **ETag caching** — clients get 304s when nothing changed
- **OpenAPI documentation** — self-describing at `/api/docs`
- **Prometheus-compatible** `/metrics` endpoint for Grafana dashboards

### 14 Data Readers

NovaControl polls local services on a 60-second cycle (Big Brother at 15s) and caches results in memory. When a consumer asks for data, it's already there.

| Reader | Source | What It Provides |
|--------|--------|-----------------|
| SystemStats | Mach/IOKit kernel APIs | CPU, RAM, disk, uptime, thermals |
| BigBrother | Diagnostics daemon :37461 | 30+ service health statuses |
| Nova | Gateway v2 :18792 | Session state, model routing |
| Ollama | Local LLM server :11434 | Loaded models, VRAM usage |
| MLXCode | MLX inference :37422 | Active model, generation stats |
| HomeKit | Shortcuts CLI proxy | Scenes, device states, execution |
| NMAP | NMAPScanner container | Network topology, host discovery |
| Rsync | RsyncGUI app support | Backup job history, sync status |
| Plex | Synology Plex :32400 | Libraries, now playing, sessions |
| Calendar | ICS/CalDAV feeds | Upcoming events, scheduling |
| NewsSummary | App support JSON | Processed news items |
| UNAS | UniFi UNAS Pro 8 state | Storage pools, drive health, RAID |
| Synology | RS1221+ state | CPU, RAM, network, disk I/O |
| HealthKit | iOS health export | Step count, activity, vitals |

### 7-Tab SwiftUI Dashboard

Click the menu bar icon and get a full operational picture:

1. **System Health** — CPU, memory, disk, thermals, uptime
2. **Services** — All monitored services with live status indicators
3. **Network** — Topology map, connected hosts, port scan results
4. **Workflows** — Automation engine status, recent triggers
5. **AI** — Ollama models, VRAM allocation, generation activity
6. **NAS** — UNAS Pro 8 and Synology RS1221+ health panels
7. **Calendar** — Upcoming events from all synced calendars

### Workflow Automation Engine

NovaControl doesn't just read data — it acts on it:

- **Slack integration** — Post alerts, summaries, scheduled messages
- **Jira integration** — Create issues from detected problems
- **Email triggers** — Send notifications on threshold breaches
- **Webhooks** — Generic HTTP callbacks for any automation

### HomeKit Integration

The standalone HomeKitControl app was absorbed into NovaControl. Scene execution and device status are now API routes, callable by any Nova component without a separate process.

---

## Ecosystem Position

NovaControl is the connective tissue. Every component in the Nova ecosystem routes through it.

```mermaid
graph TB
    subgraph "Nova Ecosystem"
        BRAIN[nova<br/>The Brain<br/>AI Gateway + Memory]
        TV[NovaTV<br/>The Display<br/>Apple TV Dashboard]
        HEALTH[NovaHealth<br/>The Body<br/>Fitness + Vitals]
        JOURNAL[nova-journal<br/>The Voice<br/>Hugo Blog + GitHub Pages]
        SCHED[Nova Scheduler<br/>Cron + Content Pipeline]
    end

    subgraph "NovaControl — The One Ring"
        NC[NovaControl<br/>:37400<br/>Unified API Gateway]
    end

    subgraph "Infrastructure"
        UNAS[UniFi UNAS Pro 8]
        SYN[Synology RS1221+]
        PG[(PostgreSQL 17<br/>+ pgvector)]
        REDIS[(Redis)]
        OLLAMA[Ollama<br/>Local LLMs]
        MLX[MLX Server<br/>Apple Silicon Inference]
        HK[HomeKit<br/>Smart Home]
        PLEX[Plex Media Server]
    end

    subgraph "Consumers"
        CLAUDE[Claude Code<br/>Development Agent]
        SLACK[Slack Bot]
        BB[Big Brother<br/>Self-Healing Daemon]
    end

    BRAIN <-->|session state, memory| NC
    TV -->|dashboard data| NC
    HEALTH -->|vitals, activity| NC
    JOURNAL -->|content stats| NC
    SCHED -->|trigger workflows| NC

    NC -->|reads state| UNAS
    NC -->|reads state| SYN
    NC -->|health probes| PG
    NC -->|health probes| REDIS
    NC -->|model status| OLLAMA
    NC -->|inference proxy| MLX
    NC -->|scene execution| HK
    NC -->|library data| PLEX

    CLAUDE -->|API calls| NC
    SLACK -->|notifications| NC
    BB -->|health checks| NC

    style NC fill:#2a6,color:#fff,stroke:#fff,stroke-width:3px
    style BRAIN fill:#5535ff,color:#fff
    style TV fill:#e6a817,color:#000
    style HEALTH fill:#c55,color:#fff
    style JOURNAL fill:#38d,color:#fff
```

---

## Internal Architecture

```mermaid
graph LR
    subgraph "Entry Points"
        HTTP[HTTP Requests<br/>:37400]
        MENU[Menu Bar Click]
        TIMER[60s Timer]
    end

    subgraph "Core"
        API[NovaAPIServer<br/>NWListener<br/>44+ routes]
        DM[DataManager<br/>Coordinator]
        WE[WorkflowEngine]
        DASH[SwiftUI Dashboard<br/>7 tabs]
    end

    subgraph "Reader Layer"
        R1[SystemStatsReader]
        R2[BigBrotherReader 15s]
        R3[NovaReader]
        R4[OllamaReader]
        R5[MLXCodeReader]
        R6[HomeKitReader]
        R7[NMAPReader]
        R8[RsyncReader]
        R9[PlexReader]
        R10[CalendarReader]
        R11[NewsSummaryReader]
        R12[UNASReader]
        R13[SynologyReader]
        R14[HealthKitReader]
    end

    HTTP --> API
    MENU --> DASH
    TIMER --> DM

    API --> DM
    DM --> WE
    DM --> R1 & R2 & R3 & R4 & R5 & R6 & R7 & R8 & R9 & R10 & R11 & R12 & R13 & R14

    DASH --> DM

    style API fill:#2a6,color:#fff
    style DM fill:#38d,color:#fff
    style WE fill:#c55,color:#fff
    style R2 fill:#a35,color:#fff
```

---

## API Route Categories

```mermaid
graph TD
    subgraph "NovaControl API — 44+ Routes"
        direction TB

        subgraph "System & Health"
            S1[GET /api/system/stats]
            S2[GET /api/health]
            S3[GET /api/health/snapshot]
            S4[GET /metrics — Prometheus]
            S5[GET /api/bigbrother/*]
        end

        subgraph "AI & Models"
            A1[GET /api/ai/models]
            A2[GET /api/ai/status]
            A3[GET /api/nova/session]
            A4[GET /api/nova/memory]
            A5[GET /api/mlxcode/*]
        end

        subgraph "Infrastructure"
            I1[GET /api/nmap/hosts]
            I2[GET /api/nmap/topology]
            I3[GET /api/unas/*]
            I4[GET /api/synology/*]
            I5[GET /api/plex/*]
        end

        subgraph "Applications"
            AP1[GET /api/oneonone/*]
            AP2[GET /api/rsync/*]
            AP3[GET /api/news/*]
            AP4[GET /api/calendar/*]
        end

        subgraph "Automation"
            W1[GET/POST /api/workflows]
            W2[GET /api/topology]
            W3[GET /api/graph]
            W4[POST /api/homekit/scenes]
            W5[GET /api/docs — OpenAPI]
        end
    end

    style S1 fill:#2a6,color:#fff
    style A1 fill:#5535ff,color:#fff
    style I1 fill:#38d,color:#fff
    style AP1 fill:#e6a817,color:#000
    style W1 fill:#c55,color:#fff
```

---

## Why It Matters

### For the AI

Nova's brain doesn't need to know about 14 different data sources, file formats, ports, and authentication mechanisms. It knows one endpoint: `localhost:37400`. Ask any question about the infrastructure and the answer is one HTTP call away.

### For Reliability

Big Brother watches NovaControl. NovaControl watches everything else. If a service dies, NovaControl still serves its last-known state from cache. The 15-second Big Brother cycle means problems are detected in under 30 seconds.

### For Development

Adding a new data source means writing one Swift reader conforming to a protocol. Register it with DataManager, add a route, done. The framework handles caching, ETag generation, error responses, and dashboard integration.

### For Operations

One process to monitor. One port to firewall. One log to read. Prometheus scraping works out of the box. The menu bar dashboard gives instant visibility without opening a browser.

---

## Technical Details

| Property | Value |
|----------|-------|
| Platform | macOS 14.0+ (Sonoma) |
| Language | Swift 5.9 |
| UI Framework | SwiftUI |
| Network | Network.framework (NWListener) |
| Port | 37400 (localhost only) |
| Refresh Cycle | 60s standard / 15s Big Brother |
| API Format | JSON with ETag caching |
| Documentation | OpenAPI 3.0 at `/api/docs` |
| Metrics | Prometheus text format at `/metrics` |
| License | MIT |
| Version | 1.4.0 |

---

## The Ecosystem

NovaControl is one of five components that make up Nova:

| Component | Role | Analogy |
|-----------|------|---------|
| **nova** | AI gateway, memory, reasoning | The Brain |
| **NovaControl** | API gateway, monitoring, automation | The Nervous System |
| **NovaTV** | Apple TV dashboard display | The Eyes |
| **NovaHealth** | Fitness tracking, vitals | The Body |
| **nova-journal** | Auto-published blog, daily content | The Voice |

NovaControl is the nervous system — it doesn't think, but nothing works without it. Every signal passes through it. Every status check routes through it. Every automation triggers from it.

---

## One Port to Rule Them All

```
curl http://localhost:37400/api/health
```

That's it. One call tells you if your entire infrastructure is healthy. No service discovery. No port scanning. No guessing what's running.

NovaControl is always watching. NovaControl always knows.

---

*Built by Jordan Koch. MIT Licensed. Part of the Nova ecosystem.*

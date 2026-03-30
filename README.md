# NovaControl

![Build](https://github.com/kochj23/NovaControl/actions/workflows/build.yml/badge.svg)
![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Port](https://img.shields.io/badge/API-port%2037400-orange)

**A macOS menu bar app that consolidates the APIs of five apps into one — so you don't have to keep them all running.**

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

## API

All routes on `http://127.0.0.1:37400` (loopback only).

```bash
# Health check
curl http://127.0.0.1:37400/api/status

# OneOnOne
curl http://127.0.0.1:37400/api/oneonone/meetings
curl http://127.0.0.1:37400/api/oneonone/actionitems
curl http://127.0.0.1:37400/api/oneonone/people

# NMAPScanner
curl http://127.0.0.1:37400/api/nmap/devices
curl http://127.0.0.1:37400/api/nmap/threats
curl -X POST http://127.0.0.1:37400/api/nmap/scan -d '{"ip":"192.168.1.0/24"}'

# RsyncGUI
curl http://127.0.0.1:37400/api/rsync/jobs
curl http://127.0.0.1:37400/api/rsync/history
curl -X POST http://127.0.0.1:37400/api/rsync/jobs/{id}/run

# System (TopGUI replacement)
curl http://127.0.0.1:37400/api/system/stats
curl http://127.0.0.1:37400/api/system/processes

# News
curl http://127.0.0.1:37400/api/news/breaking
curl http://127.0.0.1:37400/api/news/articles/{category}
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
└── Views/
    └── StatusWindowView.swift    # 4-tab SwiftUI status window
```

---

## License

MIT License — see [LICENSE](LICENSE)

Written by Jordan Koch

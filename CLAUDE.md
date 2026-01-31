# CLAUDE.md

Instructions for Claude Code when working on this repository.

## Project Overview

**Mon Réseau** — macOS app (Swift/Cocoa) for monitoring internet connectivity and network quality. Supports two modes: menu bar only (`LSUIElement`) or full application (Dock + main menu). Features a "Geek Mode" to show/hide technical tools. All UI is in French. Fully App Store compatible (no shell commands, sandboxed).

- **Bundle ID:** `com.SmartColibri.MonReseau`
- **Deployment target:** macOS 13.0+
- **Dependencies:** None — system frameworks only

## Build & Run

```bash
# Debug build
xcodebuild -project MonReseau.xcodeproj -scheme MonReseau -configuration Debug build

# Release build
xcodebuild -project MonReseau.xcodeproj -scheme MonReseau -configuration Release build

# Run (after build)
open ~/Library/Developer/Xcode/DerivedData/MonReseau-*/Build/Products/Debug/MonReseau.app
```

CLI arguments: `--traceroute`, `--speedtest`, `--details`, `--quality`

## Constraints

These rules **must** be followed for every change:

1. **No shell commands** — never use `Process()` or `NSTask`. All functionality via system APIs only.
2. **App Sandbox** — outgoing network connections allowed, nothing else. No file system access outside container.
3. **French UI** — all user-facing strings in French.
4. **No external dependencies** — no SPM, CocoaPods, or Carthage. Only system frameworks.
5. **Programmatic UI** — no storyboards, no XIBs. All views built in code.
6. **HTTPS only** — all external URLs must use HTTPS (ATS compliance).

## Architecture

13 Swift files in `MonReseau/`, ~8,400 LOC total:

| File | LOC | Role |
|------|-----|------|
| `main.swift` | 19 | Entry point, NSApplication setup |
| `AppDelegate.swift` | 838 | Dual-mode (menubar/app), NWPathMonitor, NSMenuDelegate, window coordination, VPN detection, notifications, uptime tracking, global shortcuts, appearance |
| `MainWindowController.swift` | 258 | App mode home window with card grid, Geek Mode filtering |
| `SettingsWindowController.swift` | 303 | App mode, login item, notifications, menu bar latency, appearance (System/Light/Dark), Geek Mode toggle |
| `GuideWindowController.swift` | 237 | Documentation: app overview, network concepts, optimization tips, keyboard shortcuts |
| `TeletravailWindowController.swift` | 686 | Remote work diagnostic (latency, jitter, loss, speed, DNS, VPN) |
| `NetworkDetailWindowController.swift` | 751 | Split-view: interfaces, WiFi, routing, DNS, public IP |
| `NetworkQualityWindowController.swift` | 709 | Latency/jitter/packet-loss graph (ICMP ping) |
| `SpeedTestWindowController.swift` | 952 | Download/upload speed test + history + geolocation |
| `DNSWindowController.swift` | 957 | DNS queries (all record types) + latency benchmarks |
| `TracerouteWindowController.swift` | 707 | Visual traceroute with MapKit |
| `WiFiWindowController.swift` | 674 | WiFi details + live RSSI graph |
| `NeighborhoodWindowController.swift` | 1327 | LAN device scanner + port scan + device detail |

## Frameworks & System APIs

| Framework | Usage |
|-----------|-------|
| Cocoa (AppKit) | All UI |
| Network | NWPathMonitor, NWBrowser (Bonjour) |
| SystemConfiguration | SCDynamicStore (routing, DNS config) |
| CoreWLAN | WiFi interface info |
| CoreLocation | GPS location |
| MapKit | Traceroute map |
| ServiceManagement | SMAppService (login item) |
| UserNotifications | Connection change alerts |
| dnssd | DNSServiceQueryRecord |

**Native sockets:**
- ICMP: `socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)` — ping, traceroute
- UDP: ARP solicitation, raw DNS queries
- TCP: Non-blocking `connect()` + `poll()` for port scanning
- ioctl: `SIOCGIFFLAGS` (0xc0206911), `SIOCGIFMTU` (0xc0206933)
- sysctl: ARP table via `CTL_NET/PF_ROUTE/NET_RT_FLAGS/RTF_LLINFO`

## External APIs

| Service | Purpose | Used in |
|---------|---------|---------|
| `speed.cloudflare.com` | Speed test (download/upload) | SpeedTest |
| `one.one.one.one` | Latency measurement (HEAD) | SpeedTest |
| `ipify.org` / `api6.ipify.org` | Public IP detection | NetworkDetail |
| `ipwho.is` | Hop geolocation | Traceroute |
| `ipapi.co` | IP geolocation fallback | SpeedTest |

## Data Storage

All via UserDefaults (sandbox-compatible):

- **Speed test history:** Key `SpeedTestHistory`, JSON-encoded, max 50 entries
- **App mode:** Key `AppMode`, string (`"menubar"` or `"app"`)
- **Geek Mode:** Key `GeekMode`, bool — shows/hides technical tools
- **Notify connection changes:** Key `NotifyConnectionChange`, bool
- **Menu bar latency:** Key `MenuBarShowLatency`, bool — live ping in status item
- **Appearance:** Key `AppAppearance`, string (`"system"`, `"light"`, `"dark"`) — app theme
- **Connection events:** Key `ConnectionEvents`, JSON-encoded, max 500 entries (uptime tracking)
- **Login item:** Managed by SMAppService (system-level)

Path: `~/Library/Containers/com.SmartColibri.MonReseau/Data/Library/Preferences/com.SmartColibri.MonReseau.plist`

## Custom Views

- **NetworkGraphView** — Latency/jitter/packet-loss graph (Core Graphics, 120 data points)
- **RSSIGraphView** — WiFi signal strength graph (Core Graphics, 120 data points)
- **SpeedTestAnimationView** — Wave/particle animation (CVDisplayLink, 60 fps)

## Implemented Features (from ideas)

- **Notifications** — Connection change alerts via UserNotifications (configurable in Settings)
- **VPN Detection** — Detects utun (IPv4 only), ppp, ipsec interfaces; shown in status menu
- **Menu Bar Stats** — Live ping latency displayed next to status icon (configurable in Settings)
- **Keyboard Shortcuts** — Global Ctrl+Option+letter hotkeys for all windows
- **Connection Uptime Tracker** — Logs connection events, calculates 24h uptime % and disconnection count
- **Geek Mode** — Toggle to show/hide technical tools (status menu, app menu, main window grid). Option+click on status item to toggle.
- **Dual Mode** — Menu bar only or full application (Dock + main menu + home window)
- **Guide / Documentation** — In-app guide with network concepts, optimization tips, keyboard shortcuts
- **Appearance Setting** — System/Light/Dark theme toggle in Settings, adaptive SpeedTest gradient
- **Accessibility** — VoiceOver labels on status item, main window cards, NetworkGraphView, RSSIGraphView, RSSIGaugeView
- **Localization (Phase 1)** — `fr.lproj` + `en.lproj` Localizable.strings for AppDelegate, Settings, MainWindow, Guide (~180 keys). Remaining windows not yet localized.

## Feature Ideas

Potential additions that respect all constraints (sandbox, no shell, App Store compatible):

1. **Export / Share** — Export speed test history as CSV, copy network details or traceroute results to clipboard, share via NSSharingServicePicker.

2. **Network Quality History** — Persist latency/jitter/packet-loss data over time (like speed test history). Show trends across hours/days.

3. **Configurable Ping Target** — Let users choose the ping destination (currently hardcoded 8.8.8.8). Useful for monitoring internal servers or specific hosts.

4. **IPv6 Support** — Extend traceroute, ping, and neighborhood scanner to support IPv6 networks (ICMPv6 sockets, IPv6 neighbor discovery).

5. **Bandwidth Monitor** — Track per-interface bytes in/out using `getifaddrs()` counters (already available). Display real-time throughput graph and daily/weekly totals.

6. **Localization Phase 2** — Localize remaining windows (NetworkDetail, NetworkQuality, SpeedTest, Traceroute, DNS, WiFi, Neighborhood, Teletravail).

7. **iPad / iPhone version** — Port to iOS/iPadOS.



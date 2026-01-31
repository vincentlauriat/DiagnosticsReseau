# CLAUDE.md

Instructions for Claude Code when working on this repository.

## Project Overview

**Mon Réseau** — macOS menu bar app (Swift/Cocoa) for monitoring internet connectivity and network quality. Runs as a status bar item without Dock icon (`LSUIElement = true`). All UI is in French. Fully App Store compatible (no shell commands, sandboxed).

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

10 Swift files in `MonReseau/`, ~6,100 LOC total:

| File | LOC | Role |
|------|-----|------|
| `main.swift` | 19 | Entry point, NSApplication setup |
| `AppDelegate.swift` | 338 | Menu bar status item, NWPathMonitor, window coordination |
| `SettingsWindowController.swift` | 133 | Dock visibility + launch at login |
| `NetworkDetailWindowController.swift` | 675 | Split-view: interfaces, WiFi, routing, DNS, public IP |
| `NetworkQualityWindowController.swift` | 531 | Latency/jitter/packet-loss graph (ICMP ping) |
| `SpeedTestWindowController.swift` | 904 | Download/upload speed test + history + geolocation |
| `DNSWindowController.swift` | 957 | DNS queries (all record types) + latency benchmarks |
| `TracerouteWindowController.swift` | 707 | Visual traceroute with MapKit |
| `WiFiWindowController.swift` | 514 | WiFi details + live RSSI graph |
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
- **Dock visibility:** Key `ShowInDock`
- **Login item:** Managed by SMAppService (system-level)

Path: `~/Library/Containers/com.SmartColibri.MonReseau/Data/Library/Preferences/com.SmartColibri.MonReseau.plist`

## Custom Views

- **NetworkGraphView** — Latency/jitter/packet-loss graph (Core Graphics, 120 data points)
- **RSSIGraphView** — WiFi signal strength graph (Core Graphics, 120 data points)
- **SpeedTestAnimationView** — Wave/particle animation (CVDisplayLink, 60 fps)

## Feature Ideas

Potential additions that respect all constraints (sandbox, no shell, App Store compatible):

1. **Notifications** — UserNotifications alerts when connection drops, quality degrades, or speed test completes. Configurable thresholds in settings.

2. **Export / Share** — Export speed test history as CSV, copy network details or traceroute results to clipboard, share via NSSharingServicePicker.

3. **Network Quality History** — Persist latency/jitter/packet-loss data over time (like speed test history). Show trends across hours/days.

4. **Configurable Ping Target** — Let users choose the ping destination (currently hardcoded 8.8.8.8). Useful for monitoring internal servers or specific hosts.

5. **IPv6 Support** — Extend traceroute, ping, and neighborhood scanner to support IPv6 networks (ICMPv6 sockets, IPv6 neighbor discovery).

6. **Connection Uptime Tracker** — Log connection up/down events with timestamps. Display uptime percentage and outage timeline in a dedicated window.

7. **Bandwidth Monitor** — Track per-interface bytes in/out using `getifaddrs()` counters (already available). Display real-time throughput graph and daily/weekly totals.

8. **VPN Detection** — Detect active VPN connections via interface names (utun*) and NWPath properties. Show VPN status in the menu bar and detail window.

9. **Menu Bar Stats** — Show live stats directly in the menu bar text (e.g., current latency, download speed, or RSSI) as a user-configurable option.

10. **Keyboard Shortcuts** — Global hotkeys to open specific windows (traceroute, speed test, etc.) via `NSEvent.addGlobalMonitorForEvents`.

11. **Dark/Light Theme Polish** — Ensure all custom Core Graphics views adapt properly to dark mode using `NSAppearance` checks and semantic colors.

12. **Accessibility** — Add VoiceOver labels to custom views, status items, and interactive elements. Support dynamic type where applicable.

13. **Localization Preparation** — Extract hardcoded French strings to `Localizable.strings` to enable future multi-language support without code changes.

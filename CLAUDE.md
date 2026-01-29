# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Mon Réseau** — application macOS de barre de menus (Swift/Cocoa) qui surveille la connectivité internet et la qualité réseau. Tourne comme élément de barre d'état sans icône Dock (`LSUIElement = true`). Toute l'interface est en français. Compatible App Store (aucune commande shell, entièrement sandboxée).

## Build Commands

```bash
# Build
xcodebuild -project MonReseau.xcodeproj -scheme MonReseau -configuration Debug build

# Build release
xcodebuild -project MonReseau.xcodeproj -scheme MonReseau -configuration Release build

# Run the app (after build)
open ~/Library/Developer/Xcode/DerivedData/MonReseau-*/Build/Products/Debug/MonReseau.app
```

No external dependencies — uses only system frameworks (Network, SystemConfiguration, CoreWLAN, CoreLocation, MapKit, Cocoa, ServiceManagement, dnssd).

## Architecture

Ten Swift source files in `MonReseau/`, no storyboards — all UI is built programmatically:

- **main.swift** — App entry point, sets up NSApplication with AppDelegate.
- **AppDelegate.swift** — Manages the menu bar status item and NWPathMonitor for connectivity state. Color-coded icon: green (connected), red (disconnected). Hosts menu with links to all feature windows, settings, and About. Supports command-line arguments (`--traceroute`, `--speedtest`, `--details`, `--quality`).
- **SettingsWindowController.swift** — Settings window with two options: show/hide Dock icon (`NSApp.setActivationPolicy`) and launch at login (`SMAppService`).
- **NetworkDetailWindowController.swift** — Split-view window (sidebar + detail pane) showing comprehensive network info: connection status, interfaces (ifaddrs API), WiFi details (CoreWLAN), routing (SCDynamicStore), interface flags/MTU (ioctl), DNS (SystemConfiguration), public IP (ipify.org). Auto-refreshes every 5 seconds.
- **NetworkQualityWindowController.swift** — Real-time latency/jitter/packet-loss graph with 60-second moving average. Pings 8.8.8.8 every second via native ICMP socket (`SOCK_DGRAM, IPPROTO_ICMP`), keeps 120 data points. Contains `NetworkGraphView` (custom NSView with Core Graphics drawing). Quality ratings: Excellente / Bonne / Moyenne / Mauvaise.
- **SpeedTestWindowController.swift** — Speed test with history and location tracking. Contains:
  - `SpeedTestResult` / `SpeedTestHistoryEntry` — Data models (Codable)
  - `SpeedTestHistoryStorage` — Persists history to UserDefaults (max 50 entries)
  - `LocationService` — Gets location via CoreLocation (GPS) with fallback to IP geolocation (ipapi.co)
  - `SpeedTestAnimationView` — Animated waves/particles via CVDisplayLink during test
  - HTTP-based: download from `speed.cloudflare.com/__down`, upload to `speed.cloudflare.com/__up`, latency via HEAD requests to `one.one.one.one`
- **DNSWindowController.swift** — DNS query module. Query any record type (A, AAAA, MX, NS, TXT, CNAME, SOA, PTR, ANY, or all at once). Uses `DNSServiceQueryRecord` (dnssd) for system DNS, raw UDP packets for custom DNS servers. Includes DNS latency test across public servers, system DNS config display, and cache flush command clipboard copy.
- **TracerouteWindowController.swift** — Visual traceroute with MapKit. Native ICMP implementation with TTL manipulation via `setsockopt(IP_TTL)`. 2 queries per hop, max 30 hops. Geolocates hops in real-time via ipwho.is and displays route on an interactive map. Clicking a table row highlights the hop on the map.
- **WiFiWindowController.swift** — Real-time WiFi information window. Displays SSID, BSSID, security, RSSI, noise, SNR, channel, band, width, TX rate, PHY mode, and country code via CoreWLAN. Includes RSSI signal gauge and live RSSI graph (120 data points, refreshed every 2 seconds). Contains `RSSIGraphView` (custom NSView with Core Graphics).
- **NeighborhoodWindowController.swift** — Network neighborhood scanner. 3-phase discovery: UDP sweep (ARP solicitation), ICMP ping sweep, ARP table analysis (sysctl). Enriches results with DNS reverse lookup (getnameinfo), Bonjour/mDNS service discovery (NWBrowser), and MAC vendor lookup (OUI table). Double-click opens device detail window with ping x10 stats, TCP port scan (16 common ports), and device type inference. Contains `NetworkDevice` model, `NetworkScanner` service, and `DeviceDetailWindowController`.

## Key Implementation Details

- No shell commands or `Process()` calls — fully App Store compatible
- Native ICMP sockets: `socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)` (non-privileged on macOS). Note: macOS returns IP header before ICMP payload on SOCK_DGRAM.
- ARP table reading via `sysctl(CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO)` — read-only, sandbox compatible
- TCP port scanning via non-blocking `connect()` + `poll()`
- Network info via BSD sockets ioctl (`0xc0206911` for SIOCGIFFLAGS, `0xc0206933` for SIOCGIFMTU)
- Routing info via `SCDynamicStoreCopyValue` with key `State:/Network/Global/IPv4`
- DNS queries via `DNSServiceQueryRecord` and raw UDP DNS packets with manual response parsing
- WiFi info via `CWWiFiClient.shared().interface()` (CoreWLAN)
- All external URLs use HTTPS (ATS compliant)
- Geolocation APIs: ipwho.is (traceroute), ipapi.co (speed test location)
- App Sandbox enabled with outgoing network connections allowed
- Location permission required for GPS (fallback to IP geolocation if denied)
- Launch at login via `SMAppService.mainApp` (ServiceManagement framework)
- Dock visibility toggle via `NSApp.setActivationPolicy(.regular / .accessory)`
- Deployment target: macOS 13.0+

## Data Storage

Speed test history stored in UserDefaults (sandbox-compatible):
```
~/Library/Containers/com.SmartColibri.MonReseau/Data/Library/Preferences/com.SmartColibri.MonReseau.plist
```

Max 50 entries, JSON-encoded under key `SpeedTestHistory`.

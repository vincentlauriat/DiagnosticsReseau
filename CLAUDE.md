# CLAUDE.md

Instructions for Claude Code when working on this repository.

## Project Overview

**NetDisco** — macOS app (Swift/Cocoa) for monitoring internet connectivity and network quality. Supports two modes: menu bar only (`LSUIElement`) or full application (Dock + main menu). Features a "Geek Mode" to show/hide technical tools. All UI is in French. Fully App Store compatible (no shell commands, sandboxed).

- **Bundle ID:** `com.SmartColibri.NetDisco`
- **Deployment target:** macOS 13.0+
- **Dependencies:** None — system frameworks only

## Build & Run

```bash
# Debug build
xcodebuild -project NetDisco.xcodeproj -scheme NetDisco -configuration Debug build

# Release build
xcodebuild -project NetDisco.xcodeproj -scheme NetDisco -configuration Release build

# Run (after build)
open ~/Library/Developer/Xcode/DerivedData/NetDisco-*/Build/Products/Debug/NetDisco.app
```

CLI arguments: `--traceroute`, `--speedtest`, `--details`, `--quality`

## macOS Development

**Sandbox Entitlements:**
- When adding new app modes or features that affect network access, always verify sandbox entitlements are properly configured before testing
- Check `Info.plist` and `.entitlements` files for required permissions
- Common pitfalls: missing network client entitlement, incorrect outgoing connections configuration

**Mode Switching:**
- When implementing mode-switching features (menu bar ↔ application mode), test the transition multiple times
- Add deliberate delays for async operations to avoid race conditions
- Watch for timing and memory issues that cause crashes
- Verify state cleanup when switching between modes

## Testing

**Mode Testing:**
- After implementing mode-switching features, test both modes thoroughly
- Watch for timing/memory issues that cause crashes
- Test edge cases: rapid mode switching, state persistence, window cleanup

**Race Conditions:**
- Be vigilant about async operations, especially in:
  - Network monitoring (NWPathMonitor callbacks)
  - ICMP socket operations
  - Thread-unsafe functions like `inet_ntoa`
- Add synchronization where needed (DispatchQueue, locks)

## Refactoring

**Project Renaming:**
- When renaming projects or replacing references (e.g., InternetCheck → MonReseau → NetDisco), update ALL files:
  - Swift source files
  - Documentation (README, CLAUDE.md)
  - Code comments
  - Bundle identifiers (Info.plist)
  - Directory names
  - Build configurations
  - Commit messages
- Use project-wide search to ensure no references are missed

## Constraints

These rules **must** be followed for every change:

1. **No shell commands** — never use `Process()` or `NSTask`. All functionality via system APIs only.
2. **App Sandbox** — outgoing network connections allowed, nothing else. No file system access outside container.
3. **French UI** — all user-facing strings in French.
4. **No external dependencies** — no SPM, CocoaPods, or Carthage. Only system frameworks.
5. **Programmatic UI** — no storyboards, no XIBs. All views built in code.
6. **HTTPS only** — all external URLs must use HTTPS (ATS compliance).

## Architecture

26 Swift files in `NetDisco/`, ~19,000 LOC total:

| File | LOC | Role |
|------|-----|------|
| `main.swift` | 19 | Entry point, NSApplication setup |
| `AppDelegate.swift` | ~1300 | Dual-mode (menubar/app), NWPathMonitor, NSMenuDelegate, window coordination, VPN detection, notifications, uptime tracking, global shortcuts, appearance, URL scheme handler, scheduled quality tests, network profile tracking, IP change monitoring |
| `MainWindowController.swift` | ~280 | App mode home window with card grid, Geek Mode filtering |
| `SettingsWindowController.swift` | ~750 | Tabbed settings (General, Notifications, Advanced, Profiles): app mode, login item, appearance, notifications, menu bar stats, ping target, Geek Mode, network profiles, scheduled tests config |
| `GuideWindowController.swift` | ~237 | Documentation: app overview, network concepts, optimization tips, keyboard shortcuts |
| `TeletravailWindowController.swift` | ~850 | Remote work diagnostic (latency, jitter, loss, speed, DNS, VPN) + PDF export |
| `NetworkDetailWindowController.swift` | ~800 | Split-view: interfaces, WiFi, routing, DNS, public IP, detailed VPN info |
| `NetworkQualityWindowController.swift` | ~850 | Latency/jitter/packet-loss graph (ICMP ping) + 24h quality history + interactive tooltips |
| `SpeedTestWindowController.swift` | ~980 | Download/upload speed test + history + geolocation + CSV export + profile snapshots |
| `DNSWindowController.swift` | ~1100 | DNS queries (all record types) + latency benchmarks + syntax coloring + favorites |
| `TracerouteWindowController.swift` | ~830 | Visual traceroute with MapKit, IPv4/IPv6 dual-stack + favorites |
| `WiFiWindowController.swift` | ~720 | WiFi details + live RSSI graph + interactive tooltips |
| `NeighborhoodWindowController.swift` | ~1327 | LAN device scanner + port scan + device detail |
| `BandwidthWindowController.swift` | ~400 | Real-time bandwidth monitor (getifaddrs), throughput graph, session totals |
| `WhoisWindowController.swift` | ~500 | WHOIS lookup via NWConnection TCP port 43, auto-redirect, 27 TLDs + syntax coloring + favorites |
| `AppIntents.swift` | ~220 | Siri Shortcuts via App Intents framework (8 intents with French phrases) |
| `iCloudSyncManager.swift` | ~370 | Optional iCloud sync via NSUbiquitousKeyValueStore for history, favorites, settings |
| `MTRWindowController.swift` | ~600 | MTR (My Traceroute): traceroute + continuous ping with real-time stats per hop |
| `MultiPingWindowController.swift` | ~550 | Simultaneous ping to multiple targets with comparative graph |
| `HTTPTestWindowController.swift` | ~500 | HTTP/HTTPS availability and response time testing |
| `SSLInspectorWindowController.swift` | ~550 | SSL certificate inspection (subject, issuer, validity, chain) |
| `WakeOnLANWindowController.swift` | ~450 | Wake on LAN: send magic packets to wake devices |
| `DashboardWindowController.swift` | ~700 | Real-time dashboard with connection, latency, throughput, WiFi, alerts |
| `IPChangeMonitor.swift` | ~300 | Public IP change detection service with notification |
| `AutoAnalyzer.swift` | ~250 | Automatic network problem detection with suggestions |
| `MultiTargetGraphView.swift` | ~350 | Multi-series graph view for Multi-ping and Dashboard |

## Frameworks & System APIs

| Framework | Usage |
|-----------|-------|
| Cocoa (AppKit) | All UI |
| Network | NWPathMonitor, NWBrowser (Bonjour), NWConnection (WHOIS TCP) |
| SystemConfiguration | SCDynamicStore (routing, DNS config) |
| CoreWLAN | WiFi interface info |
| CoreLocation | GPS location |
| MapKit | Traceroute map |
| ServiceManagement | SMAppService (login item) |
| UserNotifications | Connection change alerts, quality degradation, speed test completion |
| AppIntents | Siri Shortcuts integration (8 intents) |
| dnssd | DNSServiceQueryRecord |
| WidgetKit / SwiftUI | Home screen widgets (small, medium, large) |

**Native sockets:**
- ICMP: `socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)` — ping, traceroute
- ICMPv6: `socket(AF_INET6, SOCK_DGRAM, IPPROTO_ICMPV6)` — IPv6 traceroute
- UDP: ARP solicitation, raw DNS queries
- TCP: Non-blocking `connect()` + `poll()` for port scanning; NWConnection for WHOIS
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
| WHOIS servers (port 43) | Domain/IP registration info | Whois |

## Data Storage

All via UserDefaults (sandbox-compatible):

- **Speed test history:** Key `SpeedTestHistory`, JSON-encoded, max 50 entries
- **Quality history:** Key `QualityHistory`, JSON-encoded — 24h latency/jitter/loss snapshots
- **App mode:** Key `AppMode`, string (`"menubar"` or `"app"`)
- **Geek Mode:** Key `GeekMode`, bool — shows/hides technical tools
- **Notify connection changes:** Key `NotifyConnectionChange`, bool
- **Notify quality degradation:** Key `NotifyQualityDegradation`, bool + `NotifyLatencyThreshold` (double, default 100ms) + `NotifyLossThreshold` (double, default 5%)
- **Notify speed test complete:** Key `NotifySpeedTestComplete`, bool
- **Menu bar display:** Key `MenuBarDisplayMode`, string (`"none"`, `"latency"`, `"throughput"`, `"rssi"`)
- **Custom ping target:** Key `CustomPingTarget`, string (default `"8.8.8.8"`)
- **Appearance:** Key `AppAppearance`, string (`"system"`, `"light"`, `"dark"`) — app theme
- **Connection events:** Key `ConnectionEvents`, JSON-encoded, max 500 entries (uptime tracking)
- **Query favorites:** Key `QueryFavorites`, JSON-encoded, max 20 entries (DNS/Whois/Traceroute targets)
- **Network profiles:** Key `NetworkProfiles`, JSON-encoded, max 30 profiles with performance snapshots
- **Scheduled test results:** Key `ScheduledTestResults`, JSON-encoded, max 288 entries (raw ICMP results)
- **Daily reports:** Key `DailyReports`, JSON-encoded, max 30 days (compiled quality summaries)
- **Scheduled quality test:** Key `ScheduledQualityTestEnabled` (bool), `ScheduledQualityTestInterval` (int, minutes), `ScheduledDailyNotification` (bool)
- **IP change monitoring:** Key `IPChangeMonitoringEnabled` (bool), `IPChangeInterval` (int, minutes), `LastKnownPublicIP` (string), `LastKnownPublicIPv6` (string), `IPChangeHistory` (JSON-encoded, max 50)
- **Wake on LAN devices:** Key `WoLDevices`, JSON-encoded list of {name, mac, lastUsed}
- **HTTP test history:** Key `HTTPTestHistory`, JSON-encoded, max 20 entries
- **Login item:** Managed by SMAppService (system-level)

Path: `~/Library/Containers/com.SmartColibri.NetDisco/Data/Library/Preferences/com.SmartColibri.NetDisco.plist`

## Custom Views

- **NetworkGraphView** — Latency/jitter/packet-loss graph (Core Graphics, 120 data points) + interactive tooltips
- **RSSIGraphView** — WiFi signal strength graph (Core Graphics, 120 data points) + interactive tooltips
- **SpeedTestAnimationView** — Wave/particle animation (CVDisplayLink, 60 fps)
- **BandwidthGraphView** — Real-time throughput graph (Core Graphics, 120 data points, dual curves in/out)
- **QualityHistoryGraphView** — 24h quality history dual-axis graph (latency/jitter + loss%)
- **MultiTargetGraphView** — Multi-series comparison graph (Core Graphics, 120 data points, color-coded targets)

## URL Scheme

`netdisco://` deep links for widgets and external navigation:
- `netdisco://speedtest`, `netdisco://details`, `netdisco://quality`, `netdisco://traceroute`
- `netdisco://dns`, `netdisco://wifi`, `netdisco://neighborhood`, `netdisco://bandwidth`
- `netdisco://whois`, `netdisco://teletravail`, `netdisco://settings`
- `netdisco://mtr`, `netdisco://multiping`, `netdisco://httptest`, `netdisco://ssl`
- `netdisco://wol`, `netdisco://dashboard`

## Widgets (WidgetKit)

- **SmallWidget** — Connection icon + status
- **MediumWidget** — Status + last speed test (deep link `netdisco://details`)
- **LargeWidget** — Detailed status + "Run speed test" button (`netdisco://speedtest`)

## Implemented Features

- **Notifications** — Connection change, quality degradation (configurable thresholds), speed test completion alerts
- **VPN Detection** — Detailed detection of utun (IPv4 only), ppp, ipsec interfaces with addresses; dedicated section in NetworkDetail
- **Menu Bar Stats** — Live latency, throughput, or RSSI displayed next to status icon (configurable in Settings)
- **Keyboard Shortcuts** — Global Ctrl+Option+letter hotkeys for all windows
- **Connection Uptime Tracker** — Logs connection events, calculates 24h uptime % and disconnection count
- **Geek Mode** — Toggle to show/hide technical tools (status menu, app menu, main window grid). Option+click on status item to toggle.
- **Dual Mode** — Menu bar only or full application (Dock + main menu + home window)
- **Guide / Documentation** — In-app guide with network concepts, optimization tips, keyboard shortcuts
- **Appearance Setting** — System/Light/Dark theme toggle in Settings, adaptive SpeedTest gradient
- **Accessibility** — VoiceOver labels on status item, main window cards, NetworkGraphView, RSSIGraphView, RSSIGaugeView, SpeedTestAnimationView, BandwidthGraphView, Teletravail indicators
- **Localization** — `fr.lproj` + `en.lproj` Localizable.strings (~400+ keys). Phase 1: AppDelegate, Settings, MainWindow, Guide. Phase 2: NetworkDetail, NetworkQuality, SpeedTest, Traceroute, Teletravail, Whois.
- **Export / Share** — Speed test history CSV export, clipboard copy
- **Network Quality History** — 24h latency/jitter/loss persistence with trend graph
- **Configurable Ping Target** — User-defined ping destination (Settings → Advanced)
- **IPv6 Traceroute** — Dual-stack IPv4/IPv6 support (AF_UNSPEC, ICMPv6)
- **Bandwidth Monitor** — Real-time per-interface throughput via getifaddrs() counters
- **Whois Lookup** — WHOIS queries via NWConnection TCP, auto TLD server detection, redirect following
- **Interactive Graph Tooltips** — Mouse tracking with cursor line and value bubbles on NetworkGraphView and RSSIGraphView
- **Tabbed Settings** — Settings reorganized into 4 tabs (General, Notifications, Advanced, Profiles)
- **Widget Deep Links** — WidgetKit widgets with `netdisco://` URL scheme navigation
- **Query Favorites** — Save frequent DNS/Whois/Traceroute targets (★ button + popup, UserDefaults, max 20)
- **Syntax Coloring** — NSAttributedString colorization: IPs in blue, errors in red, headers bold, keys in teal (DNS, Whois, Traceroute)
- **PDF Export** — Generate A4 PDF report from Teletravail diagnostic (CGContext, NSSavePanel)
- **Network Profiles** — Named WiFi profiles (SSID-based), automatic detection, performance snapshots from speed tests
- **Scheduled Quality Tests** — Background ICMP ping at configurable intervals (5/15/30/60 min), daily reports with latency/jitter/loss stats
- **Siri Shortcuts (App Intents)** — 8 intents for Siri and Shortcuts app: speed test, network details, quality, traceroute, WiFi info, teletravail diagnostic, DNS query, WHOIS query. French phrases supported.
- **iCloud Sync** — Optional NSUbiquitousKeyValueStore sync for history, favorites, profiles, and settings. Graceful fallback when iCloud unavailable. Requires iCloud capability in provisioning profile.
- **MTR (My Traceroute)** — Traceroute + continuous ping with real-time statistics per hop (latency, jitter, loss). ICMP socket with PID/seq validation.
- **Multi-ping** — Simultaneous ping to multiple targets (Google, Cloudflare, gateway, custom) with comparative graph and statistics.
- **HTTP/HTTPS Test** — Test website availability and response time, SSL certificate status, redirect chain tracking.
- **SSL Certificate Inspector** — Inspect SSL certificates: subject, issuer, validity dates, serial number, algorithm, certificate chain.
- **IP Change Detection** — Background monitoring of public IP (IPv4/IPv6) via ipify.org with notification on change.
- **Wake on LAN** — Send magic packets to wake devices on LAN. Device management with MAC address storage.
- **Dashboard** — Real-time monitoring dashboard: connection status, latency, throughput, WiFi signal, public IP, 24h quality, alerts.
- **Auto Analyzer** — Automatic network problem detection with suggestions (high latency, packet loss, slow DNS, weak WiFi, VPN overhead).

## Feature Ideas

Potential additions that respect all constraints (sandbox, no shell, App Store compatible):

### Complétées

1. ~~**Export / Partage**~~ — ✅ Copy+Share sur tous les écrans (SpeedTest CSV, Traceroute, NetworkDetail, DNS, Quality, Teletravail, Whois)
2. ~~**Historique qualité persistant**~~ — ✅ QualityHistoryStorage (2880 snapshots, 24h, graphe historique)
3. ~~**IPv6 traceroute**~~ — ✅ AF_INET6, ICMPv6 type 128, détection auto IPv4/IPv6
4. ~~**Localisation complète**~~ — ✅ ~600 clés fr/en couvrant tous les écrans
5. ~~**Copier IP publique**~~ — ✅ Menu "Copier l'IP publique" dans le status menu

6. ~~**Favoris Whois/DNS/Traceroute**~~ — ✅ Bouton ★ + popup favoris dans DNS, Whois, Traceroute (UserDefaults, max 20)
7. ~~**Coloration syntaxique résultats**~~ — ✅ NSAttributedString : IPs en bleu, erreurs en rouge, headers en gras, clés en teal
8. ~~**Export PDF diagnostic**~~ — ✅ PDF A4 depuis Teletravail (CGContext, NSSavePanel, indicateurs + tableau + verdict)
9. ~~**Profils réseau nommés**~~ — ✅ Profils WiFi par SSID, détection auto, snapshots performance, onglet Profils dans Réglages
10. ~~**Alertes planifiées**~~ — ✅ Tests ICMP automatiques (5/15/30/60 min), rapports journaliers, notification quotidienne

### Idées futures

#### Fonctionnalités réseau (Complétées)

- ~~**MTR (My Traceroute)**~~ — ✅ Traceroute + ping continu avec stats en temps réel par hop
- ~~**Multi-ping**~~ — ✅ Ping simultané vers plusieurs cibles avec graphe comparatif
- ~~**Test HTTP/HTTPS**~~ — ✅ Disponibilité et temps de réponse de sites web + état SSL
- ~~**Certificat SSL**~~ — ✅ Infos certificat (sujet, émetteur, validité, chaîne)
- ~~**Détection changement IP**~~ — ✅ Notification quand l'IP publique change (IPv4/IPv6)
- ~~**Wake on LAN**~~ — ✅ Magic packets pour réveiller des appareils

#### Visualisation & rapports

- **Timeline déconnexions** — Graphe visuel des périodes connecté/déconnecté sur 7/30 jours
- **Comparaison de profils** — Comparer les performances entre différents réseaux WiFi
- **Rapports hebdo/mensuels** — Résumé automatique avec tendances et alertes
- **Zoom sur graphiques** — Sélection de période sur les graphes (1h, 6h, 24h, 7j)

#### Intégration système (Complétée)

- ~~**Raccourcis Siri**~~ — ✅ App Intents implémentés (8 intents avec phrases françaises)
- ~~**Synchronisation iCloud**~~ — ✅ NSUbiquitousKeyValueStore pour historique, favoris, profils
- ~~**Widget Notification Center**~~ — ✅ WidgetKit avec 3 tailles (small, medium, large)

#### Diagnostic avancé (Complété)

- ~~**Analyse automatique**~~ — ✅ Détection de problèmes avec suggestions (latence, perte, DNS, WiFi, VPN)
- ~~**Monitoring continu**~~ — ✅ Dashboard avec refresh automatique de toutes les stats

#### Diagnostic satellite (Starlink, HughesNet, Viasat...)

- **Détection de micro-coupures** — Ping rapide (intervalle 100ms) pour détecter les handovers satellite et obstructions momentanées
- **Statistiques de latence avancées** — Percentiles P50/P95/P99 + histogramme de distribution des latences
- **Test de stabilité longue durée** — Ping sur 1-6h avec graphe des interruptions et temps de rétablissement
- **Profil "Satellite"** — Seuils d'alerte ajustés (100ms normal pour GEO, 40ms pour LEO type Starlink)
- **Mesure du buffer bloat** — Test de latence sous charge (pendant téléchargement) pour détecter la congestion
- **Journal météo/interruptions** — Horodatage des problèmes pour corrélation manuelle avec conditions météo




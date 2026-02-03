# NetDisco — Documentation technique

## Vue d'ensemble

NetDisco est une application macOS qui surveille la connectivite internet et fournit des outils d'analyse reseau. Elle supporte deux modes : barre de menus (sans icone Dock) ou application classique (Dock + fenetre d'accueil). Un « Mode Geek » permet d'afficher ou masquer les outils techniques. L'application est entierement compatible App Store (aucun appel shell).

## Schema d'architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         NetDisco.app                          │
│              (macOS — mode barre de menus ou app)               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  main.swift ──> AppDelegate (NSMenuDelegate)                    │
│                    │                                            │
│                    ├── NWPathMonitor (surveillance connexion)   │
│                    ├── UNUserNotificationCenter (alertes)       │
│                    ├── UptimeTracker (suivi connexion)          │
│                    ├── VPN detection (utun/ppp/ipsec)           │
│                    ├── Global shortcuts (Ctrl+Option+lettre)    │
│                    │                                            │
│                    ├── Mode barre de menus :                    │
│                    │   ├── NSStatusItem (icone vert/rouge)      │
│                    │   ├── Option+clic = toggle Mode Geek       │
│                    │   └── Ping latence en temps reel            │
│                    │                                            │
│                    ├── Mode application :                       │
│                    │   ├── MainWindowController (grille)        │
│                    │   └── NSMenu (barre de menus macOS)        │
│                    │                                            │
│                    └── Fenetres ──┬── Details reseau  [geek]    │
│                                   ├── Qualite reseau  [geek]    │
│                                   ├── Test de debit   [geek]    │
│                                   ├── Traceroute      [geek]    │
│                                   ├── DNS             [geek]    │
│                                   ├── WiFi            [geek]    │
│                                   ├── Voisinage       [geek]    │
│                                   ├── Bande passante  [geek]    │
│                                   ├── Whois           [geek]    │
│                                   ├── Teletravail               │
│                                   ├── Guide                     │
│                                   ├── Reglages                  │
│                                   └── A propos                  │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                      Fenetres (NSWindowController)              │
├────────────────┬────────────────┬───────────────────────────────┤
│                │                │                               │
│  NetworkDetail │  NetworkQuality│  SpeedTest                    │
│  WindowCtrl    │  WindowCtrl    │  WindowCtrl                   │
│                │                │                               │
│  ┌──────────┐  │  ┌──────────┐  │  ┌──────────────────┐         │
│  │ ifaddrs  │  │  │ ICMP     │  │  │ HTTP (Cloudflare)│         │
│  │ CoreWLAN │  │  │ Socket   │  │  │ Download/Upload  │         │
│  │ ioctl    │  │  │ (ping)   │  │  │ HEAD latence     │         │
│  │ SCDynamic│  │  └──────────┘  │  ├──────────────────┤         │
│  │ ipify.org│  │                │  │ LocationService  │         │
│  └──────────┘  │  NetworkGraph  │  │ (CoreLocation +  │         │
│                │  View (CG)     │  │  ipapi.co)       │         │
│                │                │  ├──────────────────┤         │
│                │                │  │ HistoryStorage   │         │
│                │                │  │ (UserDefaults)   │         │
│                │                │  ├──────────────────┤         │
│                │                │  │ AnimationView    │         │
│                │                │  │ (CVDisplayLink)  │         │
│                │                │  └──────────────────┘         │
│                │                │                               │
├────────────────┼────────────────┼───────────────────────────────┤
│                │                │                               │
│  Traceroute    │  DNS           │  WiFi          │ Neighborhood │
│  WindowCtrl    │  WindowCtrl    │  WindowCtrl    │ WindowCtrl   │
│                │                │                │              │
│  ┌──────────┐  │  ┌──────────┐  │  ┌──────────┐  │ ┌───────────┐│
│  │ ICMP +   │  │  │ dnssd    │  │  │ CoreWLAN │  │ │ UDP sweep ││
│  │ TTL      │  │  │ (system) │  │  │ CWWiFi   │  │ │ (ARP trig)││
│  │ Socket   │  │  │ UDP raw  │  │  │ Client   │  │ ├───────────┤│
│  └──────────┘  │  │ (custom) │  │  └──────────┘  │ │ ICMP ping ││
│  ┌──────────┐  │  └──────────┘  │                │ │ sweep     ││
│  │ ipwho.is │  │                │  RSSIGraphView │ ├───────────┤│
│  │ (geoloc) │  │                │  Core Graphics │ │ ARP table ││
│  └──────────┘  │                │                │ │ (sysctl)  ││
│  ┌──────────┐  │                │                │ ├───────────┤│
│  │ MapKit   │  │                │                │ │ NWBrowser ││
│  │ (carte)  │  │                │                │ │ (Bonjour) ││
│  └──────────┘  │                │                │ ├───────────┤│
│                │                │                │ │ OUI table ││
│                │                │                │ │ Port scan ││
│                │                │                │ └───────────┘│
└────────────────┴────────────────┴────────────────┴───── ────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     Frameworks systeme                          │
├──────────┬──────────┬──────────┬──────────┬──────────┬──────────┤
│  Cocoa   │ Network  │ SysConf  │ CoreWLAN │ CoreLoc  │  MapKit  │
│  (AppKit)│ (NWPath) │ (SCDyn)  │ (WiFi)   │ (GPS)    │ (Carte)  │
├──────────┴──────────┴──────────┴──────────┴──────────┴──────────┤
│  UserNotifications  │  ServiceManagement   │  dnssd              │
├─────────────────────┴──────────────────────┴────────────────────┤
│  Darwin (BSD sockets, ioctl, ICMP, getifaddrs)                  │
└─────────────────────────────────────────────────────────────────┘
```

## Fichiers source

| Fichier | Lignes | Description |
|---------|--------|-------------|
| `main.swift` | ~19 | Point d'entree, configure NSApplication |
| `AppDelegate.swift` | ~1100 | Double mode (menubar/app), NWPathMonitor, NSMenuDelegate, coordination fenetres, VPN, notifications, uptime, raccourcis globaux, apparence, tests qualite planifies, suivi profils reseau |
| `MainWindowController.swift` | ~256 | Fenetre d'accueil mode app, grille de cartes avec filtrage Mode Geek |
| `SettingsWindowController.swift` | ~750 | Reglages par onglets (General, Notifications, Avance, Profils) : mode affichage, login item, apparence, notifications, barre de menus, ping, Mode Geek, profils reseau, config tests planifies |
| `GuideWindowController.swift` | ~237 | Documentation : presentation app, concepts reseau, astuces optimisation, raccourcis |
| `TeletravailWindowController.swift` | ~850 | Diagnostic teletravail (latence, jitter, pertes, debit, DNS, VPN) + export PDF |
| `NetworkDetailWindowController.swift` | ~751 | Details reseau complets (interfaces, WiFi, routage, DNS, IP publique) |
| `NetworkQualityWindowController.swift` | ~709 | Graphe qualite reseau temps reel (latence, jitter, pertes, moyenne mobile) |
| `SpeedTestWindowController.swift` | ~980 | Test de debit HTTP avec historique, localisation et snapshots profils |
| `DNSWindowController.swift` | ~1100 | Requetes DNS multi-types, test latence serveurs, config systeme, coloration syntaxique, favoris |
| `TracerouteWindowController.swift` | ~830 | Traceroute visuel ICMP avec carte MapKit interactive, favoris |
| `WiFiWindowController.swift` | ~674 | Informations WiFi temps reel avec graphe RSSI |
| `NeighborhoodWindowController.swift` | ~1327 | Scan voisinage (ARP+ICMP+Bonjour), details machine, scan de ports |
| `BandwidthWindowController.swift` | ~400 | Moniteur bande passante temps reel (getifaddrs), graphe debit, totaux session |
| `WhoisWindowController.swift` | ~500 | Recherche WHOIS via NWConnection TCP port 43, redirection auto, 27 TLDs, coloration syntaxique, favoris |

## APIs et protocoles reseau

### ICMP natif (ping et traceroute)
```
socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)  // Socket non-privilegie
setsockopt(IPPROTO_IP, IP_TTL, ...)         // TTL pour traceroute
sendto() / recv()                            // Envoi/reception ICMP
```
- **Ping** : Echo Request (type 8) → Echo Reply (type 0)
- **Traceroute** : TTL incrementiel (1..30) → Time Exceeded (type 11) ou Echo Reply

### Informations reseau
```
getifaddrs()                                // Liste des interfaces
ioctl(sock, 0xc0206911, &ifr)              // SIOCGIFFLAGS (flags interface)
ioctl(sock, 0xc0206933, &ifr)              // SIOCGIFMTU (MTU interface)
SCDynamicStoreCopyValue("State:/Network/Global/IPv4")  // Passerelle par defaut
```

### DNS
```
DNSServiceQueryRecord()                     // Requete DNS via le resolver systeme
socket(AF_INET, SOCK_DGRAM, 0) + UDP       // Requete DNS brute vers serveur specifique
```
- Construction manuelle du paquet DNS (header + question)
- Parsing complet de la reponse (decompression des noms, types A/AAAA/MX/NS/TXT/CNAME/SOA/PTR)

### WiFi (CoreWLAN)
```
CWWiFiClient.shared().interface()           // Interface WiFi par defaut
client.ssid() / bssid() / rssiValue()       // Infos connexion
client.wlanChannel() / transmitRate()        // Canal et debit
client.security() / activePHYMode()          // Securite et standard
```

### Voisinage reseau (scan local)
```
socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)   // UDP sweep → sollicitation ARP
socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)  // Ping sweep (Echo Request/Reply)
sysctl(CTL_NET, PF_ROUTE, 0, AF_INET,      // Lecture table ARP (MAC addresses)
       NET_RT_FLAGS, RTF_LLINFO)
getnameinfo(..., NI_NAMEREQD)               // Resolution DNS inverse
NWBrowser(for: .bonjour(...))               // Decouverte services mDNS
socket(AF_INET, SOCK_STREAM, 0) + poll()    // Scan de ports TCP (non-bloquant)
```
- **Phase 1** : UDP sweep sur port 39127 pour forcer les resolutions ARP
- **Phase 2** : Ping ICMP sweep (semaphore 20, timeout 800ms)
- **Phase 3** : Lecture table ARP → machines silencieuses (firewall, IoT)
- **Enrichissement** : DNS inverse, Bonjour (17 types de services), OUI vendor lookup
- **Detail machine** : ping x10 (stats min/max/avg/med/jitter), 16 ports TCP, type d'appareil

### WHOIS (NWConnection TCP)
```
NWConnection(host: whoisServer, port: 43, using: .tcp)
connection.send(content: query)            // Envoi domaine ou IP
connection.receive(...)                     // Lecture recursive de la reponse
```
- Detection automatique du serveur WHOIS selon le TLD (27 TLDs supportes)
- Suivi des redirections (ReferralServer, refer, Registrar WHOIS Server)
- Support IP (ARIN) et domaines
- Encodage : UTF-8, Latin-1, ASCII (fallback)

### Bande passante (getifaddrs)
```
getifaddrs()                               // Compteurs octets in/out par interface
ifi_ibytes / ifi_obytes                     // Via if_data dans ifaddrs
```
- Echantillonnage toutes les secondes, calcul du debit instantane
- Graphe temps reel (Core Graphics, 120 points)
- Totaux session par interface

### Test de debit (HTTP)
| Phase | URL | Methode |
|-------|-----|---------|
| Latence | `https://one.one.one.one` | HEAD x5, mediane |
| Download | `https://speed.cloudflare.com/__down?bytes=25000000` | GET 25 Mo |
| Upload | `https://speed.cloudflare.com/__up` | POST 10 Mo |

RPM estime : `60000 / max(latence_ms, 5)`

## Services externes (HTTPS)

| Service | Usage | Rate limit |
|---------|-------|------------|
| `ipwho.is` | Geolocalisation des hops (traceroute) | Pas de limite stricte |
| `ipapi.co` | Localisation IP (test de debit) | 1000/jour (gratuit) |
| `ipify.org` | IP publique | Illimite |
| `speed.cloudflare.com` | Test de debit (download/upload) | Pas de limite |
| `one.one.one.one` | Mesure de latence | Pas de limite |

## Stockage des donnees

### Historique des tests de debit
- **Emplacement** : `UserDefaults` (cle `SpeedTestHistory`)
- **Format** : JSON (`[SpeedTestHistoryEntry]`, Codable)
- **Limite** : 50 entrees maximum
- **Champs** : date, downloadMbps, uploadMbps, latencyMs, rpm, location, isFallback

### Autres cles UserDefaults
- `AppMode` : `"menubar"` ou `"app"` — mode d'affichage
- `GeekMode` : bool — affiche/masque les outils techniques
- `NotifyConnectionChange` : bool — notifications connexion/deconnexion
- `MenuBarShowLatency` : bool — ping en temps reel dans la barre de menus
- `MenuBarDisplayMode` : `"none"`, `"latency"`, `"throughput"` ou `"rssi"` — stat affichee dans la barre de menus
- `NotifyQualityDegradation` : bool — notifications degradation qualite
- `NotifyLatencyThreshold` : double — seuil latence (defaut 100 ms)
- `NotifyLossThreshold` : double — seuil perte de paquets (defaut 5%)
- `NotifySpeedTestComplete` : bool — notification fin test de debit
- `CustomPingTarget` : string — cible ping personnalisee (defaut 8.8.8.8)
- `QualityHistory` : JSON — historique qualite reseau 24h
- `AppAppearance` : `"system"`, `"light"` ou `"dark"` — theme de l'application
- `ConnectionEvents` : JSON `[ConnectionEvent]`, max 500 — suivi d'uptime
- `QueryFavorites` : JSON `[QueryFavorite]`, max 20 — cibles favorites DNS/Whois/Traceroute
- `NetworkProfiles` : JSON `[NetworkProfile]`, max 30 — profils reseau nommes avec snapshots performance
- `ScheduledTestResults` : JSON `[ScheduledTestResult]`, max 288 — resultats tests qualite planifies
- `DailyReports` : JSON `[DailyReport]`, max 30 — rapports journaliers compiles
- `ScheduledQualityTestEnabled` : bool — active/desactive les tests planifies
- `ScheduledQualityTestInterval` : int — intervalle en minutes (5, 15, 30, 60)
- `ScheduledDailyNotification` : bool — notification rapport quotidien

### Sandbox
```
~/Library/Containers/com.SmartColibri.NetDisco/Data/Library/Preferences/
```

## Vues personnalisees (Core Graphics)

### NetworkGraphView
- Graphe de latence en temps reel (120 points, 1/seconde)
- Courbe verte (latence), aire orange (jitter), barres rouges (pertes)
- Courbe bleue pointillee (moyenne mobile 60s)
- Grille adaptive, labels en ms

### RSSIGraphView
- Graphe RSSI en temps reel (120 points, 1 toutes les 2s)
- Courbe bleue avec aire remplie
- Points colores : vert (> -50), orange (-50 a -70), rouge (< -70)
- Zones de qualite en fond (vert/orange/rouge)
- Echelle -100 a -20 dBm

### SpeedTestAnimationView
- Animation de vague/particules pendant le test de debit
- Pilotee par CVDisplayLink (60 fps)

### BandwidthGraphView
- Graphe debit temps reel (120 points, 1/seconde)
- Deux courbes : reception (bleu) et envoi (vert)
- Echelle auto-adaptative

### Tooltips interactifs (NetworkGraphView, RSSIGraphView)
- NSTrackingArea + mouseMoved pour affichage valeurs sous le curseur
- Ligne verticale et bulle tooltip avec valeurs exactes

## Localisation

- **Langues** : francais (langue de developpement), anglais
- **Fichiers** : `fr.lproj/Localizable.strings`, `en.lproj/Localizable.strings`
- **Pattern** : `NSLocalizedString("key", comment: "")`
- **Phase 1 (fait)** : AppDelegate, SettingsWindowController, MainWindowController, GuideWindowController (~180 cles)
- **Phase 2 (fait)** : fenetres techniques partiellement localisees (NetworkDetail, NetworkQuality, SpeedTest, Traceroute, Teletravail, WhoisWindowController)
- **Cles totales** : ~400+ cles fr/en

## Accessibilite

- **Status item** : accessibilityLabel, accessibilityHelp, accessibilityValue dynamique (connecte/deconnecte)
- **MainWindow cartes** : accessibilityLabel(title), accessibilityRole(.button)
- **NetworkGraphView** : accessibilityRole(.image), accessibilityValue dynamique (latence moyenne, % perte)
- **RSSIGraphView** : accessibilityRole(.image), accessibilityValue dynamique (signal dBm)
- **RSSIGaugeView** : accessibilityRole(.levelIndicator), accessibilityValue dynamique
- **SpeedTestAnimationView** : accessibilityElement(false) (decoratif)
- **NetworkDetailWindowController** : accessibilityDescription sur les icones de section

## Apparence

- **Reglage** : Systeme / Clair / Sombre (NSSegmentedControl dans Settings)
- **Stockage** : UserDefaults cle `AppAppearance`
- **Application** : `AppDelegate.applyAppearance()` via `NSApp.appearance`
- **SpeedTestAnimationView** : gradient adaptatif (clair/sombre via `effectiveAppearance`)

## Entitlements et permissions

```xml
<!-- NetDisco.entitlements -->
App Sandbox = YES
Outgoing Connections (Client) = YES

<!-- Info.plist -->
LSUIElement = true                    (mode barre de menus par defaut, bascule via setActivationPolicy)
NSLocationWhenInUseUsageDescription   (localisation pour tests de debit)
CFBundleURLTypes                      (netdisco:// URL scheme pour deep links)
```

## URL Scheme

L'application enregistre le scheme `netdisco://` pour les liens profonds (widgets, liens externes) :
- `netdisco://speedtest`, `netdisco://details`, `netdisco://quality`, `netdisco://traceroute`
- `netdisco://dns`, `netdisco://wifi`, `netdisco://neighborhood`, `netdisco://bandwidth`
- `netdisco://whois`, `netdisco://teletravail`, `netdisco://settings`

## Widgets (WidgetKit)

- **SmallWidget** : icone connexion + statut
- **MediumWidget** : statut + dernier test de debit (lien `netdisco://details`)
- **LargeWidget** : statut detaille + bouton « Lancer un test de debit » (`netdisco://speedtest`)

## Build

- **IDE** : Xcode
- **Langage** : Swift
- **Cible** : macOS 13.0+
- **Dependances externes** : aucune
- **Storyboards** : aucun (UI 100% programmatique)
- **Entrypoint** : `main.swift` (pas de `@main`)

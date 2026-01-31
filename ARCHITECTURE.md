# InternetCheck — Documentation technique

## Vue d'ensemble

InternetCheck est une application macOS de barre de menus qui surveille la connectivite internet et fournit des outils d'analyse reseau. L'application fonctionne sans icone dans le dock (`LSUIElement = true`) et est entierement compatible App Store (aucun appel shell).

## Schema d'architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        InternetCheck.app                        │
│                     (macOS Menu Bar App)                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  main.swift ──> AppDelegate                                     │
│                    │                                            │
│                    ├── NWPathMonitor (surveillance connexion)   │
│                    ├── NSStatusItem (icone barre de menus)      │
│                    │                                            │
│                    └── Menu ──┬── Details reseau                │
│                               ├── Qualite reseau                │
│                               ├── Test de debit                 │
│                               ├── Traceroute                    │
│                               ├── DNS                           │
│                               ├── WiFi                          │
│                               ├── Voisinage                     │
│                               ├── A propos                      │
│                               └── Quitter                       │
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
│  Darwin (BSD sockets, ioctl, ICMP)  │  dnssd (DNS Service)      │
└─────────────────────────────────────┴───────────────────────────┘
```

## Fichiers source

| Fichier | Lignes | Description |
|---------|--------|-------------|
| `main.swift` | ~10 | Point d'entree, configure NSApplication |
| `AppDelegate.swift` | ~330 | Barre de menus, surveillance reseau, menu, fenetres |
| `NetworkDetailWindowController.swift` | ~550 | Details reseau complets (interfaces, WiFi, routage, DNS, IP publique) |
| `NetworkQualityWindowController.swift` | ~530 | Graphe qualite reseau temps reel (latence, jitter, pertes, moyenne mobile) |
| `SpeedTestWindowController.swift` | ~900 | Test de debit HTTP avec historique et localisation |
| `DNSWindowController.swift` | ~960 | Requetes DNS multi-types, test latence serveurs, config systeme |
| `TracerouteWindowController.swift` | ~580 | Traceroute visuel ICMP avec carte MapKit interactive |
| `WiFiWindowController.swift` | ~510 | Informations WiFi temps reel avec graphe RSSI |
| `NeighborhoodWindowController.swift` | ~1300 | Scan voisinage (ARP+ICMP+Bonjour), details machine, scan de ports |

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

### Sandbox
```
~/Library/Containers/com.vincent.InternetCheck/Data/Library/Preferences/
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

## Entitlements et permissions

```xml
<!-- InternetCheck.entitlements -->
App Sandbox = YES
Outgoing Connections (Client) = YES

<!-- Info.plist -->
LSUIElement = true                    (pas d'icone dock)
NSLocationWhenInUseUsageDescription   (localisation pour tests de debit)
```

## Build

- **IDE** : Xcode
- **Langage** : Swift
- **Cible** : macOS 13.0+
- **Dependances externes** : aucune
- **Storyboards** : aucun (UI 100% programmatique)
- **Entrypoint** : `main.swift` (pas de `@main`)

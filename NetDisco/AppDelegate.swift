// AppDelegate.swift
// Point central de l'application: gere le mode barre de menus et le mode application normale.
// Utilise NWPathMonitor pour suivre l'état du réseau et met à jour l'icône (vert/rouge).

// Vincent

import Cocoa
import Network
import ServiceManagement
import UserNotifications
import WidgetKit
import CoreWLAN
import CoreLocation

// MARK: - Scheduled Quality Tests

struct ScheduledTestResult: Codable {
    let date: Date
    let latency: Double
    let jitter: Double
    let packetLoss: Double
}

struct DailyReport: Codable {
    let date: Date
    let testCount: Int
    let minLatency: Double
    let maxLatency: Double
    let avgLatency: Double
    let avgJitter: Double
    let avgPacketLoss: Double
    let degradationCount: Int
    let uptimePercent: Double
}

class ScheduledTestStorage {
    private static let resultsKey = "ScheduledTestResults"
    private static let reportsKey = "DailyReports"
    private static let maxResults = 288  // 24h at 5min intervals
    private static let maxReports = 30

    static func loadResults() -> [ScheduledTestResult] {
        guard let data = UserDefaults.standard.data(forKey: resultsKey),
              let results = try? JSONDecoder().decode([ScheduledTestResult].self, from: data) else {
            return []
        }
        return results
    }

    static func saveResults(_ results: [ScheduledTestResult]) {
        let trimmed = Array(results.suffix(maxResults))
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: resultsKey)
        }
    }

    static func addResult(_ result: ScheduledTestResult) {
        var results = loadResults()
        results.append(result)
        saveResults(results)
    }

    static func loadReports() -> [DailyReport] {
        guard let data = UserDefaults.standard.data(forKey: reportsKey),
              let reports = try? JSONDecoder().decode([DailyReport].self, from: data) else {
            return []
        }
        return reports
    }

    static func saveReports(_ reports: [DailyReport]) {
        let trimmed = Array(reports.suffix(maxReports))
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: reportsKey)
        }
    }

    static func addReport(_ report: DailyReport) {
        var reports = loadReports()
        reports.append(report)
        saveReports(reports)
    }

    /// Compile les résultats d'hier en rapport journalier.
    static func compileDailyReport() -> DailyReport? {
        let results = loadResults()
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let startOfYesterday = calendar.startOfDay(for: yesterday)
        let startOfToday = calendar.startOfDay(for: Date())

        let dayResults = results.filter { $0.date >= startOfYesterday && $0.date < startOfToday }
        guard !dayResults.isEmpty else { return nil }

        let latencies = dayResults.map { $0.latency }
        let jitters = dayResults.map { $0.jitter }
        let losses = dayResults.map { $0.packetLoss }
        let threshold = UserDefaults.standard.double(forKey: "NotifyLatencyThreshold")
        let effectiveThreshold = threshold > 0 ? threshold : 100.0
        let degradations = dayResults.filter { $0.latency > effectiveThreshold }.count

        return DailyReport(
            date: startOfYesterday,
            testCount: dayResults.count,
            minLatency: latencies.min() ?? 0,
            maxLatency: latencies.max() ?? 0,
            avgLatency: latencies.reduce(0, +) / Double(latencies.count),
            avgJitter: jitters.reduce(0, +) / Double(jitters.count),
            avgPacketLoss: losses.reduce(0, +) / Double(losses.count),
            degradationCount: degradations,
            uptimePercent: UptimeTracker.uptimePercent24h()
        )
    }
}

/// AppDelegate gerant deux modes : barre de menus (status item) ou application normale (Dock + barre de menus macOS).
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, CLLocationManagerDelegate {

    // Fenêtres et surveillance
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private let monitor = NWPathMonitor()
    private let locationManager = CLLocationManager()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    private var detailWindowController: NetworkDetailWindowController?
    private var qualityWindowController: NetworkQualityWindowController?
    private var speedTestWindowController: SpeedTestWindowController?
    private var tracerouteWindowController: TracerouteWindowController?
    private var dnsWindowController: DNSWindowController?
    private var wifiWindowController: WiFiWindowController?
    private var neighborhoodWindowController: NeighborhoodWindowController?
    private var bandwidthWindowController: BandwidthWindowController?
    private var whoisWindowController: WhoisWindowController?
    private var teletravailWindowController: TeletravailWindowController?
    private var guideWindowController: GuideWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var aboutWindow: NSWindow?
    private var mainWindowController: MainWindowController?

    /// Mode courant de l'application.
    private(set) var currentMode: AppMode = .menubar

    /// Dernier etat de connexion connu (pour la barre de menus macOS).
    private var lastConnected = false
    /// Indique si on a deja recu au moins un evenement reseau (pour eviter la notification au lancement).
    private var hasReceivedFirstNetworkEvent = false
    /// Timer pour le ping en barre de menus.
    private var menuBarPingTimer: Timer?
    /// Date du dernier changement de connexion.
    private var lastConnectionChangeDate = Date()
    /// Moniteurs de raccourcis globaux.
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    /// Timer pour les tests qualité planifiés.
    private var scheduledTestTimer: Timer?
    /// Date du dernier rapport journalier compilé.
    private var lastDailyReportDate: Date?

    enum AppMode: String {
        case menubar
        case app
    }

    // Icônes pré-générées pour l'état connecté/déconnecté
    private lazy var greenIcon: NSImage = makeStatusIcon(color: .systemGreen)
    private lazy var redIcon: NSImage = makeStatusIcon(color: .systemRed)

    private func makeStatusIcon(color: NSColor) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
            color.setFill()
            circle.fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Point d'entrée après lancement: applique le mode sauvegarde.
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Demander l'autorisation pour les notifications
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        UNUserNotificationCenter.current().delegate = self

        // Demander l'autorisation de localisation (nécessaire pour accéder au SSID WiFi sur macOS Sonoma+)
        locationManager.delegate = self
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(updateGeekModeVisibility), name: Notification.Name("GeekModeChanged"), object: nil)

        applyAppearance()

        let savedMode = UserDefaults.standard.string(forKey: "AppMode") ?? "menubar"
        // Migration de l'ancien reglage ShowInDock
        if UserDefaults.standard.object(forKey: "AppMode") == nil && UserDefaults.standard.bool(forKey: "ShowInDock") {
            applyMode(.app)
        } else {
            applyMode(AppMode(rawValue: savedMode) ?? .menubar)
        }

        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let connected = path.status == .satisfied
                let wasConnected = self.lastConnected
                self.lastConnected = connected
                self.updateIcon(isConnected: connected)

                // Logger l'evenement de connexion
                if self.hasReceivedFirstNetworkEvent && connected != wasConnected {
                    self.lastConnectionChangeDate = Date()
                    UptimeTracker.logEvent(connected: connected)
                }

                // Notifications de connexion/deconnexion
                if self.hasReceivedFirstNetworkEvent && UserDefaults.standard.bool(forKey: "NotifyConnectionChange") {
                    if connected && !wasConnected {
                        self.sendNotification(title: NSLocalizedString("notification.connection_restored.title", comment: ""), body: NSLocalizedString("notification.connection_restored.body", comment: ""))
                    } else if !connected && wasConnected {
                        self.sendNotification(title: NSLocalizedString("notification.connection_lost.title", comment: ""), body: NSLocalizedString("notification.connection_lost.body", comment: ""))
                    }
                }
                self.hasReceivedFirstNetworkEvent = true
                self.updateWidgetData()

                // Mettre à jour le profil réseau si connecté
                if connected {
                    if let ssid = CWWiFiClient.shared().interface()?.ssid() {
                        NetworkProfileStorage.updateLastConnected(ssid: ssid)
                    }
                }
            }
        }
        monitor.start(queue: monitorQueue)

        // Handle command-line arguments
        processCommandLineArguments()

        // Raccourcis clavier globaux (Ctrl+Option+lettre)
        setupGlobalShortcuts()

        // Tests qualité planifiés
        startScheduledTestsIfNeeded()

        // Démarrer la synchronisation iCloud si activée
        if UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") {
            iCloudSyncManager.shared.startSync()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Arrêter la synchronisation iCloud
        iCloudSyncManager.shared.stopSync()
        monitor.cancel()
        menuBarPingTimer?.invalidate()
        scheduledTestTimer?.invalidate()
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m) }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Quand l'utilisateur clique sur l'icone Dock (mode app), ouvrir la fenetre d'accueil.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if currentMode == .app && !flag {
            showMainWindow()
        }
        return true
    }

    // MARK: - Apparence

    /// Applique le thème (système, clair ou sombre) selon les préférences.
    func applyAppearance() {
        let mode = UserDefaults.standard.string(forKey: "AppAppearance") ?? "system"
        switch mode {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    // MARK: - Gestion des modes

    /// Bascule vers le mode indique.
    func applyMode(_ mode: AppMode) {
        currentMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "AppMode")

        switch mode {
        case .menubar:
            teardownAppMode()
            setupMenubarMode()
        case .app:
            teardownMenubarMode()
            setupAppMode()
        }
    }

    private func setupMenubarMode() {
        // Passer en mode accessory si nécessaire
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
        // Supprimer tout status item existant pour eviter les doublons
        if let existing = statusItem {
            NSStatusBar.system.removeStatusItem(existing)
            statusItem = nil
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.toolTip = NSLocalizedString("statusitem.tooltip", comment: "")
        statusItem?.button?.image = lastConnected ? greenIcon : redIcon
        statusItem?.button?.imagePosition = .imageOnly
        statusItem?.button?.setAccessibilityLabel(NSLocalizedString("statusitem.accessibility_label", comment: ""))
        statusItem?.button?.setAccessibilityHelp(NSLocalizedString("statusitem.accessibility_help", comment: ""))
        setupStatusMenu()
        updateIcon(isConnected: lastConnected)
        startMenuBarPingIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func teardownMenubarMode() {
        menuBarPingTimer?.invalidate()
        menuBarPingTimer = nil
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func setupAppMode() {
        NSApp.setActivationPolicy(.regular)
        setupMainMenu()
        updateGeekModeVisibility()
        showMainWindow()
    }

    private func teardownAppMode() {
        mainWindowController?.close()
        mainWindowController = nil
        NSApp.mainMenu = nil
    }

    private func showMainWindow() {
        if mainWindowController == nil {
            mainWindowController = MainWindowController()
        }
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Barre de menus macOS (mode app)

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // Menu "Mon Reseau"
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: NSLocalizedString("appmenu.about", comment: ""), action: #selector(showAboutPanel), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: NSLocalizedString("appmenu.settings", comment: ""), action: #selector(showSettings), keyEquivalent: ","))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: NSLocalizedString("appmenu.quit", comment: ""), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Menu "Fenetre"
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: NSLocalizedString("appmenu.window", comment: ""))
        windowMenu.addItem(NSMenuItem(title: NSLocalizedString("appmenu.home", comment: ""), action: #selector(showMainWindowAction), keyEquivalent: "0"))
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(NSMenuItem(title: NSLocalizedString("menu.details", comment: ""), action: #selector(showDetails), keyEquivalent: "d"))
        windowMenu.addItem(NSMenuItem(title: NSLocalizedString("menu.quality", comment: ""), action: #selector(showQuality), keyEquivalent: "g"))
        windowMenu.addItem(NSMenuItem(title: NSLocalizedString("menu.speedtest", comment: ""), action: #selector(showSpeedTest), keyEquivalent: "t"))
        windowMenu.addItem(NSMenuItem(title: NSLocalizedString("menu.traceroute", comment: ""), action: #selector(showTraceroute), keyEquivalent: "r"))
        windowMenu.addItem(NSMenuItem(title: NSLocalizedString("menu.dns", comment: ""), action: #selector(showDNS), keyEquivalent: "n"))
        windowMenu.addItem(NSMenuItem(title: NSLocalizedString("menu.wifi", comment: ""), action: #selector(showWiFi), keyEquivalent: "w"))
        windowMenu.addItem(NSMenuItem(title: NSLocalizedString("menu.neighborhood", comment: ""), action: #selector(showNeighborhood), keyEquivalent: "b"))
        windowMenu.addItem(NSMenuItem(title: NSLocalizedString("menu.bandwidth", comment: ""), action: #selector(showBandwidth), keyEquivalent: "u"))
        windowMenu.addItem(NSMenuItem(title: NSLocalizedString("menu.whois", comment: ""), action: #selector(showWhois), keyEquivalent: "o"))
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(NSMenuItem(title: NSLocalizedString("menu.teletravail", comment: ""), action: #selector(showTeletravail), keyEquivalent: "e"))
        windowMenu.addItem(NSMenuItem(title: NSLocalizedString("menu.guide", comment: ""), action: #selector(showGuide), keyEquivalent: "h"))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func showMainWindowAction() {
        showMainWindow()
    }

    // MARK: - Menu du status item (mode barre de menus)

    private func setupStatusMenu() {
        let menu = NSMenu()
        let titleItem = NSMenuItem(title: NSLocalizedString("menu.title", comment: ""), action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        let statusTitle: String
        if lastConnected {
            statusTitle = detectVPN() ? NSLocalizedString("menu.connected_vpn", comment: "") : NSLocalizedString("menu.connected", comment: "")
        } else {
            statusTitle = NSLocalizedString("menu.checking", comment: "")
        }
        let statusMenuItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusMenuItem.tag = 1
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem(title: NSLocalizedString("menu.copyip", comment: ""), action: #selector(copyPublicIP), keyEquivalent: ""))

        let geekSep = NSMenuItem.separator()
        geekSep.tag = 100
        menu.addItem(geekSep)
        for (title, action, key) in [
            (NSLocalizedString("menu.details", comment: ""), #selector(showDetails), "d"),
            (NSLocalizedString("menu.quality", comment: ""), #selector(showQuality), "g"),
            (NSLocalizedString("menu.speedtest", comment: ""), #selector(showSpeedTest), "t"),
            (NSLocalizedString("menu.traceroute", comment: ""), #selector(showTraceroute), "r"),
            (NSLocalizedString("menu.dns", comment: ""), #selector(showDNS), "n"),
            (NSLocalizedString("menu.wifi", comment: ""), #selector(showWiFi), "w"),
            (NSLocalizedString("menu.neighborhood", comment: ""), #selector(showNeighborhood), "b"),
            (NSLocalizedString("menu.bandwidth", comment: ""), #selector(showBandwidth), "u"),
            (NSLocalizedString("menu.whois", comment: ""), #selector(showWhois), "o"),
        ] as [(String, Selector, String)] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.tag = 100
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: NSLocalizedString("menu.teletravail", comment: ""), action: #selector(showTeletravail), keyEquivalent: "e"))
        menu.addItem(NSMenuItem(title: NSLocalizedString("menu.guide", comment: ""), action: #selector(showGuide), keyEquivalent: "h"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: NSLocalizedString("menu.settings", comment: ""), action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: NSLocalizedString("menu.about", comment: ""), action: #selector(showAboutPanel), keyEquivalent: "i"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: NSLocalizedString("menu.quit", comment: ""), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.delegate = self
        statusMenu = menu
        statusItem?.menu = menu
        updateGeekModeVisibility()
    }

    /// Met à jour la visibilité des éléments techniques dans le menu status et la barre de menus app.
    @objc func updateGeekModeVisibility() {
        let geekMode = UserDefaults.standard.bool(forKey: "GeekMode")

        // Menu du status item
        if let menu = statusMenu {
            for item in menu.items where item.tag == 100 {
                item.isHidden = !geekMode
            }
        }

        // Barre de menus app (menu "Fenêtre")
        if let windowMenu = NSApp.mainMenu?.item(at: 1)?.submenu {
            for item in windowMenu.items {
                let title = item.title
                let homeTitle = NSLocalizedString("appmenu.home", comment: "")
                let teletravailTitle = NSLocalizedString("menu.teletravail", comment: "")
                let guideTitle = NSLocalizedString("menu.guide", comment: "")
                if title == homeTitle || title == teletravailTitle || title == guideTitle || item.isSeparatorItem {
                    continue
                }
                // Cacher les items techniques (Détails, Qualité, Débit, Traceroute, DNS, WiFi, Voisinage)
                item.isHidden = !geekMode
            }
        }
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        guard menu == statusMenu else { return }
        if let event = NSApp.currentEvent, event.modifierFlags.contains(.option) {
            // Option+clic : basculer le mode geek et fermer le menu
            let current = UserDefaults.standard.bool(forKey: "GeekMode")
            UserDefaults.standard.set(!current, forKey: "GeekMode")
            NotificationCenter.default.post(name: Notification.Name("GeekModeChanged"), object: nil)
            DispatchQueue.main.async {
                menu.cancelTracking()
            }
        }
    }

    /// Analyse les arguments en ligne de commande pour déclencher des actions.
    private func processCommandLineArguments() {
        let args = CommandLine.arguments

        // Ignorer le premier argument (chemin de l'app)
        var i = 1
        while i < args.count {
            let arg = args[i]

            // Lance la fenetre Traceroute (optionnellement avec une cible)
            switch arg {
            case "--traceroute":
                // L'argument suivant est l'hôte
                if i + 1 < args.count {
                    let host = args[i + 1]
                    i += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.runTraceroute(host: host)
                    }
                } else {
                    showTraceroute()
                }

            // Lance immediatement un test de debit
            case "--speedtest":
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.runSpeedTest()
                }

            // Ouvre la fenetre des details reseau
            case "--details":
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.showDetails()
                }

            // Ouvre la fenetre de qualite reseau
            case "--quality":
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.showQuality()
                }

            default:
                break
            }

            i += 1
        }
    }

    // MARK: - URL Scheme (netdisco://)

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "netdisco" else { continue }
            let command = url.host ?? ""
            switch command {
            case "speedtest": performShowSpeedTest()
            case "details": performShowDetails()
            case "quality": performShowQuality()
            case "traceroute": performShowTraceroute()
            case "dns": performShowDNS()
            case "wifi": performShowWiFi()
            case "neighborhood": performShowNeighborhood()
            case "bandwidth": performShowBandwidth()
            case "whois": performShowWhois()
            case "teletravail": performShowTeletravail()
            case "settings": performShowSettings()
            default: break
            }
        }
    }

    /// Présente une fenêtre associée à un contrôleur, en l'instanciant si nécessaire, puis l'active au premier plan.
    private func present<T: NSWindowController>(_ controller: inout T?, factory: () -> T) {
        if controller == nil { controller = factory() }
        controller?.showWindow(nil)
        controller?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Ouvre la fenêtre Traceroute et démarre sur l'hôte fourni.
    private func runTraceroute(host: String) {
        present(&tracerouteWindowController) { TracerouteWindowController() }
        tracerouteWindowController?.startTraceroute(host: host)
    }

    /// Ouvre la fenêtre Test de débit et démarre le test.
    private func runSpeedTest() {
        present(&speedTestWindowController) { SpeedTestWindowController() }
        speedTestWindowController?.startTest()
    }

    // MARK: - Actions (accessibles depuis le menu et MainWindowController)

    @objc private func showQuality() {
        present(&qualityWindowController) { NetworkQualityWindowController() }
    }

    @objc private func showSpeedTest() {
        present(&speedTestWindowController) { SpeedTestWindowController() }
    }

    @objc private func showTraceroute() {
        present(&tracerouteWindowController) { TracerouteWindowController() }
    }

    @objc private func showDNS() {
        present(&dnsWindowController) { DNSWindowController() }
    }

    @objc private func showWiFi() {
        present(&wifiWindowController) { WiFiWindowController() }
    }

    @objc private func showNeighborhood() {
        present(&neighborhoodWindowController) { NeighborhoodWindowController() }
    }

    @objc private func showBandwidth() {
        present(&bandwidthWindowController) { BandwidthWindowController() }
    }

    @objc private func showWhois() {
        present(&whoisWindowController) { WhoisWindowController() }
    }

    @objc private func copyPublicIP() {
        URLSession.shared.dataTask(with: URLRequest(url: URL(string: "https://api.ipify.org")!, timeoutInterval: 5)) { data, _, _ in
            guard let data = data, let ip = String(data: data, encoding: .utf8), !ip.isEmpty else { return }
            DispatchQueue.main.async {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(ip, forType: .string)
            }
        }.resume()
    }

    @objc private func showTeletravail() {
        present(&teletravailWindowController) { TeletravailWindowController() }
    }

    @objc private func showGuide() {
        present(&guideWindowController) { GuideWindowController() }
    }

    @objc private func showSettings() {
        present(&settingsWindowController) { SettingsWindowController() }
    }

    /// Affiche la fenêtre A propos.
    @objc private func showAboutPanel() {
        if let w = aboutWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("about.title", comment: "")
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.aboutWindow = window

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]

        // Icone de l'app
        let iconSize: CGFloat = 80
        let iconView = NSImageView(frame: NSRect(
            x: (360 - iconSize) / 2, y: 190, width: iconSize, height: iconSize
        ))
        let icon = NSImage(size: NSSize(width: iconSize, height: iconSize), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4))
            NSColor.systemGreen.setFill()
            circle.fill()
            return true
        }
        iconView.image = icon
        contentView.addSubview(iconView)

        // Nom de l'app
        let nameLabel = NSTextField(labelWithString: NSLocalizedString("about.name", comment: ""))
        nameLabel.font = NSFont.boldSystemFont(ofSize: 18)
        nameLabel.alignment = .center
        nameLabel.frame = NSRect(x: 0, y: 155, width: 360, height: 28)
        contentView.addSubview(nameLabel)

        // Version
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let versionLabel = NSTextField(labelWithString: String(format: NSLocalizedString("about.version", comment: ""), version, build))
        versionLabel.font = NSFont.systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        versionLabel.frame = NSRect(x: 0, y: 133, width: 360, height: 20)
        contentView.addSubview(versionLabel)

        // Description
        let descLabel = NSTextField(labelWithString: NSLocalizedString("about.description", comment: ""))
        descLabel.font = NSFont.systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor
        descLabel.alignment = .center
        descLabel.maximumNumberOfLines = 2
        descLabel.frame = NSRect(x: 20, y: 95, width: 320, height: 34)
        contentView.addSubview(descLabel)

        // Credits
        let creditsLabel = NSTextField(labelWithString: NSLocalizedString("about.credits", comment: ""))
        creditsLabel.font = NSFont.systemFont(ofSize: 12)
        creditsLabel.alignment = .center
        creditsLabel.frame = NSRect(x: 0, y: 65, width: 360, height: 20)
        contentView.addSubview(creditsLabel)

        // Copyright
        let year = Calendar.current.component(.year, from: Date())
        let copyrightLabel = NSTextField(labelWithString: String(format: NSLocalizedString("about.copyright", comment: ""), year))
        copyrightLabel.font = NSFont.systemFont(ofSize: 10)
        copyrightLabel.textColor = .tertiaryLabelColor
        copyrightLabel.alignment = .center
        copyrightLabel.frame = NSRect(x: 0, y: 56, width: 360, height: 16)
        contentView.addSubview(copyrightLabel)

        // Frameworks
        let frameworksLabel = NSTextField(labelWithString: NSLocalizedString("about.frameworks", comment: ""))
        frameworksLabel.font = NSFont.systemFont(ofSize: 9)
        frameworksLabel.textColor = .tertiaryLabelColor
        frameworksLabel.alignment = .center
        frameworksLabel.frame = NSRect(x: 0, y: 38, width: 360, height: 14)
        contentView.addSubview(frameworksLabel)

        // Bouton OK
        let okButton = NSButton(title: NSLocalizedString("about.ok", comment: ""), target: self, action: #selector(closeAbout))
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"
        okButton.frame = NSRect(x: (360 - 80) / 2, y: 8, width: 80, height: 28)
        contentView.addSubview(okButton)

        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func closeAbout() {
        aboutWindow?.close()
    }

    @objc private func showDetails() {
        present(&detailWindowController) { NetworkDetailWindowController() }
    }

    /// Met à jour l'icône d'état (vert si connecté, rouge sinon) et le texte de statut.
    private func updateIcon(isConnected: Bool) {
        statusItem?.button?.image = isConnected ? greenIcon : redIcon
        statusItem?.button?.setAccessibilityValue(isConnected ? NSLocalizedString("menu.connected", comment: "") : NSLocalizedString("menu.disconnected", comment: ""))

        if let item = statusMenu?.item(withTag: 1) {
            if isConnected {
                item.title = detectVPN() ? NSLocalizedString("menu.connected_vpn", comment: "") : NSLocalizedString("menu.connected", comment: "")
            } else {
                item.title = NSLocalizedString("menu.disconnected", comment: "")
            }
        }
    }

    /// Détecte si un tunnel VPN est actif en cherchant des interfaces utun/ipsec/ppp
    /// avec une adresse IPv4 routable (les utun système n'ont généralement que du IPv6 link-local).
    private func detectVPN() -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return false }
        defer { freeifaddrs(ifaddr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = cursor {
            defer { cursor = addr.pointee.ifa_next }
            let name = String(cString: addr.pointee.ifa_name)
            let flags = Int32(addr.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0 else { continue }
            guard let sa = addr.pointee.ifa_addr else { continue }
            let family = sa.pointee.sa_family

            // Les interfaces PPP et IPSec indiquent toujours un VPN
            if name.hasPrefix("ppp") || name.hasPrefix("ipsec") {
                if family == UInt8(AF_INET) || family == UInt8(AF_INET6) {
                    return true
                }
            }

            // Pour utun : seule une adresse IPv4 indique un vrai VPN
            // (les utun système comme utun0/utun1 n'ont que des adresses IPv6 link-local)
            if name.hasPrefix("utun") && family == UInt8(AF_INET) {
                return true
            }
        }
        return false
    }

    // MARK: - Mise a jour du widget

    /// Ecrit les donnees partagees pour le widget via App Group.
    func updateWidgetData() {
        // WiFi info
        let wifiClient = CWWiFiClient.shared()
        let iface = wifiClient.interface()
        let ssid = iface?.ssid()
        let rssi = iface != nil ? iface!.rssiValue() : 0

        // Speed test history
        let history = SpeedTestHistoryStorage.load()
        let recentTests = history.prefix(3).map {
            SpeedTestSummary(date: $0.date, downloadMbps: $0.downloadMbps, uploadMbps: $0.uploadMbps, latencyMs: $0.latencyMs, location: $0.location)
        }
        let lastTest = recentTests.first

        let data = WidgetData(
            isConnected: lastConnected,
            latencyMs: nil,
            vpnActive: detectVPN(),
            wifiSSID: ssid,
            wifiRSSI: ssid != nil ? rssi : nil,
            uptimePercent: UptimeTracker.uptimePercent24h(),
            disconnections24h: UptimeTracker.disconnectionCount24h(),
            lastSpeedTest: lastTest,
            recentSpeedTests: Array(recentTests),
            latencyHistory: [],
            qualityRating: nil,
            updatedAt: Date()
        )
        saveWidgetData(data)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Raccourcis clavier globaux

    private func setupGlobalShortcuts() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard event.modifierFlags.contains([.control, .option]) else { return }
            guard let self = self else { return }

            switch event.charactersIgnoringModifiers {
            case "d": DispatchQueue.main.async { self.showDetails() }
            case "g": DispatchQueue.main.async { self.showQuality() }
            case "t": DispatchQueue.main.async { self.showSpeedTest() }
            case "r": DispatchQueue.main.async { self.showTraceroute() }
            case "n": DispatchQueue.main.async { self.showDNS() }
            case "w": DispatchQueue.main.async { self.showWiFi() }
            case "b": DispatchQueue.main.async { self.showNeighborhood() }
            case "u": DispatchQueue.main.async { self.showBandwidth() }
            case "o": DispatchQueue.main.async { self.showWhois() }
            case "e": DispatchQueue.main.async { self.showTeletravail() }
            case "h": DispatchQueue.main.async { self.showGuide() }
            default: break
            }
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains([.control, .option]) {
                handler(event)
            }
            return event
        }
    }

    // MARK: - Stats barre de menus

    /// Dernière date d'envoi d'une notification de dégradation qualité (cooldown 5 min).
    private var lastQualityNotificationDate = Date.distantPast
    /// Bytes précédents pour le calcul du débit.
    private var previousBytes: (inBytes: UInt64, outBytes: UInt64, date: Date)?

    /// Demarre ou arrete le timer periodique pour afficher des stats dans la barre de menus.
    func startMenuBarPingIfNeeded() {
        menuBarPingTimer?.invalidate()
        menuBarPingTimer = nil

        let mode = UserDefaults.standard.string(forKey: "MenuBarDisplayMode") ?? (UserDefaults.standard.bool(forKey: "MenuBarShowLatency") ? "latency" : "none")

        guard mode != "none" else {
            if let item = statusItem {
                item.length = NSStatusItem.squareLength
                item.button?.title = ""
                item.button?.imagePosition = .imageOnly
            }
            return
        }

        statusItem?.length = NSStatusItem.variableLength
        statusItem?.button?.imagePosition = .imageLeading

        menuBarPingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.performMenuBarUpdate()
        }
        performMenuBarUpdate()
    }

    private func performMenuBarUpdate() {
        let mode = UserDefaults.standard.string(forKey: "MenuBarDisplayMode") ?? "latency"

        switch mode {
        case "latency":
            let pingTarget = UserDefaults.standard.string(forKey: "CustomPingTarget") ?? "8.8.8.8"
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let latency = self?.quickPing(host: pingTarget)
                DispatchQueue.main.async {
                    guard let self = self, let button = self.statusItem?.button else { return }
                    if let lat = latency {
                        button.title = String(format: " %.0f ms", lat)
                        self.checkQualityThresholds(latencyMs: lat)
                    } else {
                        button.title = " —"
                    }
                }
            }

        case "throughput":
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let bytes = self?.readInterfaceBytes()
                DispatchQueue.main.async {
                    guard let self = self, let button = self.statusItem?.button, let current = bytes else { return }
                    if let prev = self.previousBytes {
                        let elapsed = Date().timeIntervalSince(prev.date)
                        guard elapsed > 0 else { return }
                        let inRate = Double(current.0 &- prev.inBytes) / elapsed
                        let outRate = Double(current.1 &- prev.outBytes) / elapsed
                        button.title = String(format: " ↓%@ ↑%@", self.formatRate(inRate), self.formatRate(outRate))
                    } else {
                        button.title = " ↓— ↑—"
                    }
                    self.previousBytes = (current.0, current.1, Date())
                }
            }

        case "rssi":
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let wifiClient = CWWiFiClient.shared()
                let rssi = wifiClient.interface()?.rssiValue()
                DispatchQueue.main.async {
                    guard let self = self, let button = self.statusItem?.button else { return }
                    if let r = rssi, r != 0 {
                        button.title = String(format: " %d dBm", r)
                    } else {
                        button.title = " —"
                    }
                }
            }

        default:
            break
        }
    }

    private func readInterfaceBytes() -> (UInt64, UInt64)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let addr = cursor {
            defer { cursor = addr.pointee.ifa_next }
            guard let sa = addr.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: addr.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("utun") || name.hasPrefix("ppp") else { continue }
            if let data = addr.pointee.ifa_data {
                let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                totalIn += UInt64(networkData.ifi_ibytes)
                totalOut += UInt64(networkData.ifi_obytes)
            }
        }
        return (totalIn, totalOut)
    }

    private func formatRate(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 { return String(format: "%.0f o/s", bytesPerSec) }
        if bytesPerSec < 1024 * 1024 { return String(format: "%.0f Ko/s", bytesPerSec / 1024) }
        return String(format: "%.1f Mo/s", bytesPerSec / (1024 * 1024))
    }

    /// Vérifie les seuils de qualité et envoie une notification si nécessaire.
    private func checkQualityThresholds(latencyMs: Double, lossPercent: Double = 0) {
        guard UserDefaults.standard.bool(forKey: "NotifyQualityDegradation") else { return }
        guard Date().timeIntervalSince(lastQualityNotificationDate) > 300 else { return }

        let latThreshold = UserDefaults.standard.object(forKey: "NotifyLatencyThreshold") as? Double ?? 100
        let lossThreshold = UserDefaults.standard.object(forKey: "NotifyLossThreshold") as? Double ?? 5

        if latencyMs > latThreshold {
            lastQualityNotificationDate = Date()
            sendNotification(
                title: NSLocalizedString("notification.quality_degraded.title", comment: ""),
                body: String(format: NSLocalizedString("notification.quality_degraded.latency", comment: ""), latencyMs, latThreshold)
            )
        } else if lossPercent > lossThreshold {
            lastQualityNotificationDate = Date()
            sendNotification(
                title: NSLocalizedString("notification.quality_degraded.title", comment: ""),
                body: String(format: NSLocalizedString("notification.quality_degraded.loss", comment: ""), lossPercent, lossThreshold)
            )
        }
    }

    /// Ping ICMP rapide pour la barre de menus.
    private func quickPing(host: String) -> Double? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var infoPtr: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &infoPtr) == 0, let info = infoPtr else { return nil }
        defer { freeaddrinfo(infoPtr) }

        let destAddr = info.pointee.ai_addr
        let destLen = info.pointee.ai_addrlen

        let sock = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard sock >= 0 else { return nil }
        defer { Darwin.close(sock) }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var packet = [UInt8](repeating: 0, count: 64)
        packet[0] = 8
        let ident = UInt16(ProcessInfo.processInfo.processIdentifier & 0xFFFF)
        packet[4] = UInt8(ident >> 8)
        packet[5] = UInt8(ident & 0xFF)
        let seq = UInt16.random(in: 0...UInt16.max)
        packet[6] = UInt8(seq >> 8)
        packet[7] = UInt8(seq & 0xFF)

        var sum: UInt32 = 0
        for i in stride(from: 0, to: packet.count - 1, by: 2) {
            sum += UInt32(packet[i]) << 8 | UInt32(packet[i + 1])
        }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        let checksum = ~UInt16(sum)
        packet[2] = UInt8(checksum >> 8)
        packet[3] = UInt8(checksum & 0xFF)

        let startTime = CFAbsoluteTimeGetCurrent()
        let sent = packet.withUnsafeBytes { bufPtr in
            sendto(sock, bufPtr.baseAddress, bufPtr.count, 0, destAddr, socklen_t(destLen))
        }
        guard sent > 0 else { return nil }

        var recvBuf = [UInt8](repeating: 0, count: 1024)
        let received = recv(sock, &recvBuf, recvBuf.count, 0)
        guard received > 0 else { return nil }

        return (CFAbsoluteTimeGetCurrent() - startTime) * 1000
    }

    // MARK: - Scheduled Quality Tests

    func startScheduledTestsIfNeeded() {
        scheduledTestTimer?.invalidate()
        scheduledTestTimer = nil

        guard UserDefaults.standard.bool(forKey: "ScheduledQualityTestEnabled") else { return }

        let intervalMinutes = UserDefaults.standard.integer(forKey: "ScheduledQualityTestInterval")
        let interval = TimeInterval(max(intervalMinutes, 5) * 60)

        scheduledTestTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.runScheduledQualityTest()
        }
    }

    private func runScheduledQualityTest() {
        guard lastConnected else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let target = UserDefaults.standard.string(forKey: "CustomPingTarget") ?? "8.8.8.8"
            let pingCount = 5
            var latencies: [Double] = []

            // Simple ICMP ping via socket
            var hints = addrinfo()
            hints.ai_family = AF_INET
            hints.ai_socktype = SOCK_DGRAM
            var infoPtr: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(target, nil, &hints, &infoPtr) == 0, let info = infoPtr else { return }
            defer { freeaddrinfo(infoPtr) }

            let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
            guard sock >= 0 else { return }
            defer { close(sock) }

            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

            let pid = UInt16(ProcessInfo.processInfo.processIdentifier & 0xFFFF)

            for seq in 0..<pingCount {
                var packet = [UInt8](repeating: 0, count: 64)
                packet[0] = 8  // ICMP Echo Request
                packet[1] = 0
                packet[4] = UInt8(pid >> 8)
                packet[5] = UInt8(pid & 0xFF)
                packet[6] = UInt8(seq >> 8)
                packet[7] = UInt8(seq & 0xFF)
                // Checksum
                var sum: UInt32 = 0
                for i in stride(from: 0, to: packet.count, by: 2) {
                    sum += UInt32(packet[i]) << 8
                    if i + 1 < packet.count { sum += UInt32(packet[i + 1]) }
                }
                sum = (sum >> 16) + (sum & 0xFFFF)
                sum += sum >> 16
                let checksum = ~UInt16(sum & 0xFFFF)
                packet[2] = UInt8(checksum >> 8)
                packet[3] = UInt8(checksum & 0xFF)

                let start = CFAbsoluteTimeGetCurrent()
                let sent = packet.withUnsafeBufferPointer { buf in
                    sendto(sock, buf.baseAddress, buf.count, 0, info.pointee.ai_addr, info.pointee.ai_addrlen)
                }
                guard sent > 0 else { continue }

                var recvBuf = [UInt8](repeating: 0, count: 1024)
                let received = recv(sock, &recvBuf, recvBuf.count, 0)
                if received > 0 {
                    let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                    latencies.append(elapsed)
                }
                usleep(200_000)
            }

            guard !latencies.isEmpty else { return }

            let avgLatency = latencies.reduce(0, +) / Double(latencies.count)
            let jitter: Double
            if latencies.count > 1 {
                var diffs: [Double] = []
                for i in 1..<latencies.count {
                    diffs.append(abs(latencies[i] - latencies[i-1]))
                }
                jitter = diffs.reduce(0, +) / Double(diffs.count)
            } else {
                jitter = 0
            }
            let loss = Double(pingCount - latencies.count) / Double(pingCount) * 100

            let result = ScheduledTestResult(date: Date(), latency: avgLatency, jitter: jitter, packetLoss: loss)
            ScheduledTestStorage.addResult(result)

            // Daily report compilation (check once per run)
            self?.checkDailyReportCompilation()

            // Notification if degradation
            let threshold = UserDefaults.standard.double(forKey: "NotifyLatencyThreshold")
            let effectiveThreshold = threshold > 0 ? threshold : 100.0
            if avgLatency > effectiveThreshold && UserDefaults.standard.bool(forKey: "NotifyQualityDegradation") {
                DispatchQueue.main.async {
                    self?.sendNotification(
                        title: NSLocalizedString("scheduled.degradation.title", comment: ""),
                        body: String(format: NSLocalizedString("scheduled.degradation.body", comment: ""), avgLatency, loss)
                    )
                }
            }
        }
    }

    private func checkDailyReportCompilation() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let last = lastDailyReportDate, calendar.isDate(last, inSameDayAs: today) { return }

        // Check if we already have a report for yesterday
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let existingReports = ScheduledTestStorage.loadReports()
        if existingReports.contains(where: { calendar.isDate($0.date, inSameDayAs: yesterday) }) {
            lastDailyReportDate = today
            return
        }

        if let report = ScheduledTestStorage.compileDailyReport() {
            ScheduledTestStorage.addReport(report)
            lastDailyReportDate = today

            // Daily summary notification
            if UserDefaults.standard.bool(forKey: "ScheduledDailyNotification") {
                DispatchQueue.main.async { [weak self] in
                    self?.sendNotification(
                        title: NSLocalizedString("scheduled.daily.title", comment: ""),
                        body: String(format: NSLocalizedString("scheduled.daily.body", comment: ""), report.avgLatency, report.avgPacketLoss, report.degradationCount)
                    )
                }
            }
        }
        lastDailyReportDate = today
    }

    // MARK: - API publique pour MainWindowController

    func performShowDetails() { showDetails() }
    func performShowQuality() { showQuality() }
    func performShowSpeedTest() { showSpeedTest() }
    func performShowTraceroute() { showTraceroute() }
    func performShowDNS() { showDNS() }
    func performShowWiFi() { showWiFi() }
    func performShowNeighborhood() { showNeighborhood() }
    func performShowBandwidth() { showBandwidth() }
    func performShowWhois() { showWhois() }
    func performShowTeletravail() { showTeletravail() }
    func performShowGuide() { showGuide() }
    func performShowSettings() { showSettings() }
}

extension AppDelegate {
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === aboutWindow {
            aboutWindow = nil
        }
    }
}

// MARK: - Notifications

extension AppDelegate: UNUserNotificationCenterDelegate {
    func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - CLLocationManagerDelegate

extension AppDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Quand l'autorisation change, rafraîchir les données WiFi
        // L'accès au SSID nécessite l'autorisation de localisation sur macOS Sonoma+
        DispatchQueue.main.async { [weak self] in
            self?.updateWidgetData()
        }
    }
}

// MARK: - Suivi d'uptime

struct ConnectionEvent: Codable {
    let date: Date
    let connected: Bool
}

class UptimeTracker {
    private static let key = "ConnectionEvents"
    private static let maxEvents = 500

    static func logEvent(connected: Bool) {
        var events = loadEvents()
        events.insert(ConnectionEvent(date: Date(), connected: connected), at: 0)
        if events.count > maxEvents { events = Array(events.prefix(maxEvents)) }
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func loadEvents() -> [ConnectionEvent] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let events = try? JSONDecoder().decode([ConnectionEvent].self, from: data) else {
            return []
        }
        return events
    }

    /// Calcule le pourcentage d'uptime sur les dernières 24h.
    static func uptimePercent24h() -> Double {
        let events = loadEvents()
        let now = Date()
        let cutoff = now.addingTimeInterval(-86400)

        guard !events.isEmpty else { return 100.0 }

        var totalUp: TimeInterval = 0
        var previousDate = now
        var previousConnected = true

        for event in events {
            let eventDate = max(event.date, cutoff)
            if eventDate < cutoff { break }

            if previousConnected {
                totalUp += previousDate.timeIntervalSince(eventDate)
            }
            previousDate = eventDate
            previousConnected = event.connected
        }

        // Temps restant jusqu'au cutoff
        if previousConnected && previousDate > cutoff {
            totalUp += previousDate.timeIntervalSince(cutoff)
        }

        return (totalUp / 86400) * 100
    }

    /// Compte le nombre de déconnexions dans les dernières 24h.
    static func disconnectionCount24h() -> Int {
        let cutoff = Date().addingTimeInterval(-86400)
        return loadEvents().filter { !$0.connected && $0.date > cutoff }.count
    }
}

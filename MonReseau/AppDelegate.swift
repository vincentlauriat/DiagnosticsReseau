// AppDelegate.swift
// Point central de l'application: gere le mode barre de menus et le mode application normale.
// Utilise NWPathMonitor pour suivre l'état du réseau et met à jour l'icône (vert/rouge).

// Vincent

import Cocoa
import Network
import ServiceManagement
import UserNotifications

/// AppDelegate gerant deux modes : barre de menus (status item) ou application normale (Dock + barre de menus macOS).
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {

    // Fenêtres et surveillance
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    private var detailWindowController: NetworkDetailWindowController?
    private var qualityWindowController: NetworkQualityWindowController?
    private var speedTestWindowController: SpeedTestWindowController?
    private var tracerouteWindowController: TracerouteWindowController?
    private var dnsWindowController: DNSWindowController?
    private var wifiWindowController: WiFiWindowController?
    private var neighborhoodWindowController: NeighborhoodWindowController?
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
            }
        }
        monitor.start(queue: monitorQueue)

        // Handle command-line arguments
        processCommandLineArguments()

        // Raccourcis clavier globaux (Ctrl+Option+lettre)
        setupGlobalShortcuts()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.cancel()
        menuBarPingTimer?.invalidate()
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

    /// Demarre ou arrete le ping periodique pour afficher la latence dans la barre de menus.
    func startMenuBarPingIfNeeded() {
        menuBarPingTimer?.invalidate()
        menuBarPingTimer = nil

        guard UserDefaults.standard.bool(forKey: "MenuBarShowLatency") else {
            // Remettre le status item en mode icône seule
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
            self?.performMenuBarPing()
        }
        performMenuBarPing()
    }

    private func performMenuBarPing() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let latency = self?.quickPing(host: "8.8.8.8")
            DispatchQueue.main.async {
                guard let self = self, let button = self.statusItem?.button else { return }
                if let lat = latency {
                    button.title = String(format: " %.0f ms", lat)
                } else {
                    button.title = " —"
                }
            }
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

    // MARK: - API publique pour MainWindowController

    func performShowDetails() { showDetails() }
    func performShowQuality() { showQuality() }
    func performShowSpeedTest() { showSpeedTest() }
    func performShowTraceroute() { showTraceroute() }
    func performShowDNS() { showDNS() }
    func performShowWiFi() { showWiFi() }
    func performShowNeighborhood() { showNeighborhood() }
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

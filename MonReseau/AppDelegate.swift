// AppDelegate.swift
// Point central de l'application: gere le mode barre de menus et le mode application normale.
// Utilise NWPathMonitor pour suivre l'état du réseau et met à jour l'icône (vert/rouge).

// Vincent

import Cocoa
import Network
import ServiceManagement
// Network pour NWPathMonitor (état connecté/déconnecté)

/// AppDelegate gerant deux modes : barre de menus (status item) ou application normale (Dock + barre de menus macOS).
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    // Fenêtres et surveillance
    private var statusItem: NSStatusItem?
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    private var detailWindowController: NetworkDetailWindowController?
    private var qualityWindowController: NetworkQualityWindowController?
    private var speedTestWindowController: SpeedTestWindowController?
    private var tracerouteWindowController: TracerouteWindowController?
    private var dnsWindowController: DNSWindowController?
    private var wifiWindowController: WiFiWindowController?
    private var neighborhoodWindowController: NeighborhoodWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var aboutWindow: NSWindow?
    private var mainWindowController: MainWindowController?

    /// Mode courant de l'application.
    private(set) var currentMode: AppMode = .menubar

    /// Dernier etat de connexion connu (pour la barre de menus macOS).
    private var lastConnected = false

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
        let savedMode = UserDefaults.standard.string(forKey: "AppMode") ?? "menubar"
        // Migration de l'ancien reglage ShowInDock
        if UserDefaults.standard.object(forKey: "AppMode") == nil && UserDefaults.standard.bool(forKey: "ShowInDock") {
            applyMode(.app)
        } else {
            applyMode(AppMode(rawValue: savedMode) ?? .menubar)
        }

        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.lastConnected = path.status == .satisfied
                self?.updateIcon(isConnected: path.status == .satisfied)
            }
        }
        monitor.start(queue: monitorQueue)

        // Handle command-line arguments
        processCommandLineArguments()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.cancel()
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
        // Passer en mode accessory seulement si on n'y est pas deja (LSUIElement gere le lancement)
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            statusItem?.button?.toolTip = "Mon Réseau"
        }
        setupStatusMenu()
        updateIcon(isConnected: lastConnected)
    }

    private func teardownMenubarMode() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func setupAppMode() {
        NSApp.setActivationPolicy(.regular)
        setupMainMenu()
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
        appMenu.addItem(NSMenuItem(title: "À propos de Mon Réseau", action: #selector(showAboutPanel), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Réglages…", action: #selector(showSettings), keyEquivalent: ","))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quitter Mon Réseau", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Menu "Fenetre"
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Fenêtre")
        windowMenu.addItem(NSMenuItem(title: "Accueil", action: #selector(showMainWindowAction), keyEquivalent: "0"))
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(NSMenuItem(title: "Détails réseau", action: #selector(showDetails), keyEquivalent: "d"))
        windowMenu.addItem(NSMenuItem(title: "Qualité réseau", action: #selector(showQuality), keyEquivalent: "g"))
        windowMenu.addItem(NSMenuItem(title: "Test de débit", action: #selector(showSpeedTest), keyEquivalent: "t"))
        windowMenu.addItem(NSMenuItem(title: "Traceroute", action: #selector(showTraceroute), keyEquivalent: "r"))
        windowMenu.addItem(NSMenuItem(title: "DNS", action: #selector(showDNS), keyEquivalent: "n"))
        windowMenu.addItem(NSMenuItem(title: "WiFi", action: #selector(showWiFi), keyEquivalent: "w"))
        windowMenu.addItem(NSMenuItem(title: "Voisinage", action: #selector(showNeighborhood), keyEquivalent: "b"))
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
        let titleItem = NSMenuItem(title: "Mon Réseau", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        let statusMenuItem = NSMenuItem(title: "Vérification…", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 1
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Détails réseau…", action: #selector(showDetails), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Qualité réseau…", action: #selector(showQuality), keyEquivalent: "g"))
        menu.addItem(NSMenuItem(title: "Test de débit…", action: #selector(showSpeedTest), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "Traceroute…", action: #selector(showTraceroute), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "DNS…", action: #selector(showDNS), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "WiFi…", action: #selector(showWiFi), keyEquivalent: "w"))
        menu.addItem(NSMenuItem(title: "Voisinage…", action: #selector(showNeighborhood), keyEquivalent: "b"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Réglages…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "À propos…", action: #selector(showAboutPanel), keyEquivalent: "i"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
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
        window.title = "À propos d'Mon Réseau"
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
        let nameLabel = NSTextField(labelWithString: "Mon Réseau")
        nameLabel.font = NSFont.boldSystemFont(ofSize: 18)
        nameLabel.alignment = .center
        nameLabel.frame = NSRect(x: 0, y: 155, width: 360, height: 28)
        contentView.addSubview(nameLabel)

        // Version
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let versionLabel = NSTextField(labelWithString: "Version \(version) (\(build))")
        versionLabel.font = NSFont.systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        versionLabel.frame = NSRect(x: 0, y: 133, width: 360, height: 20)
        contentView.addSubview(versionLabel)

        // Description
        let descLabel = NSTextField(labelWithString: "Surveillance de la connectivité internet\net de la qualité réseau pour macOS.")
        descLabel.font = NSFont.systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor
        descLabel.alignment = .center
        descLabel.maximumNumberOfLines = 2
        descLabel.frame = NSRect(x: 20, y: 95, width: 320, height: 34)
        contentView.addSubview(descLabel)

        // Credits
        let creditsLabel = NSTextField(labelWithString: "Développé par Vincent LAURIAT")
        creditsLabel.font = NSFont.systemFont(ofSize: 12)
        creditsLabel.alignment = .center
        creditsLabel.frame = NSRect(x: 0, y: 65, width: 360, height: 20)
        contentView.addSubview(creditsLabel)

        // Copyright
        let year = Calendar.current.component(.year, from: Date())
        let copyrightLabel = NSTextField(labelWithString: "© \(year) Vincent LAURIAT. Tous droits réservés.")
        copyrightLabel.font = NSFont.systemFont(ofSize: 10)
        copyrightLabel.textColor = .tertiaryLabelColor
        copyrightLabel.alignment = .center
        copyrightLabel.frame = NSRect(x: 0, y: 56, width: 360, height: 16)
        contentView.addSubview(copyrightLabel)

        // Frameworks
        let frameworksLabel = NSTextField(labelWithString: "Cocoa · Network · SystemConfiguration · CoreWLAN · CoreLocation")
        frameworksLabel.font = NSFont.systemFont(ofSize: 9)
        frameworksLabel.textColor = .tertiaryLabelColor
        frameworksLabel.alignment = .center
        frameworksLabel.frame = NSRect(x: 0, y: 38, width: 360, height: 14)
        contentView.addSubview(frameworksLabel)

        // Bouton OK
        let okButton = NSButton(title: "OK", target: self, action: #selector(closeAbout))
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

        if let item = statusItem?.menu?.item(withTag: 1) {
            item.title = isConnected ? "Connecté" : "Déconnecté"
        }
    }

    // MARK: - API publique pour MainWindowController

    func performShowDetails() { showDetails() }
    func performShowQuality() { showQuality() }
    func performShowSpeedTest() { showSpeedTest() }
    func performShowTraceroute() { showTraceroute() }
    func performShowDNS() { showDNS() }
    func performShowWiFi() { showWiFi() }
    func performShowNeighborhood() { showNeighborhood() }
}

extension AppDelegate {
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === aboutWindow {
            aboutWindow = nil
        }
    }
}

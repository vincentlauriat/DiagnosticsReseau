// AppDelegate.swift
// Point central de l'application (menu bar app): icône d'état, menu, fenêtres et surveillance de connectivité.
// Utilise NWPathMonitor pour suivre l'état du réseau et met à jour l'icône (vert/rouge).

// Vincent

import Cocoa
import Network
import ServiceManagement
// Network pour NWPathMonitor (état connecté/déconnecté)

/// AppDelegate d'une application barre de menus: configure l'icône d'état, le menu et les fenêtres,
/// et surveille la connectivité avec `NWPathMonitor`.
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    // Fenêtres et surveillance
    // - `statusItem`: icône dans la barre de menus
    // - `monitor`: surveille l'état réseau
    // - `detailWindowController` / `qualityWindowController` / `speedTestWindowController` / `tracerouteWindowController`: fenêtres secondaires
    private var statusItem: NSStatusItem!
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

    /// Point d'entrée après lancement: prépare le menu, l'icône et démarre la surveillance.
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.toolTip = "Mon Réseau"

        // Pas besoin de forcer l'icone — l'asset catalog s'en charge

        // Appliquer le mode Dock sauvegarde
        if UserDefaults.standard.bool(forKey: "ShowInDock") {
            NSApp.setActivationPolicy(.regular)
        }

        setupMenu()
        updateIcon(isConnected: false)

        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
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

    /// Construit le menu de la barre de menus (items et raccourcis).
    private func setupMenu() {
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

        statusItem.menu = menu
    }

    /// Affiche la fenêtre correspondante et l'active au premier plan.
    @objc private func showQuality() {
        present(&qualityWindowController) { NetworkQualityWindowController() }
    }

    /// Affiche la fenêtre correspondante et l'active au premier plan.
    @objc private func showSpeedTest() {
        present(&speedTestWindowController) { SpeedTestWindowController() }
    }

    /// Affiche la fenêtre correspondante et l'active au premier plan.
    @objc private func showTraceroute() {
        present(&tracerouteWindowController) { TracerouteWindowController() }
    }

    /// Affiche la fenêtre DNS et l'active au premier plan.
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

    /// Affiche la fenêtre correspondante et l'active au premier plan.
    @objc private func showDetails() {
        present(&detailWindowController) { NetworkDetailWindowController() }
    }

    /// Met à jour l'icône d'état (vert si connecté, rouge sinon) et le texte de statut.
    /// - Parameter isConnected: État de connectivité.
    private func updateIcon(isConnected: Bool) {
        statusItem.button?.image = isConnected ? greenIcon : redIcon

        if let item = statusItem.menu?.item(withTag: 1) {
            item.title = isConnected ? "Connecté" : "Déconnecté"
        }
    }
}

extension AppDelegate {
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === aboutWindow {
            aboutWindow = nil
        }
    }
}

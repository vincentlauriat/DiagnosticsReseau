// MainWindowController.swift
// Fenetre d'accueil du mode Application.
// Affiche une grille de boutons pour acceder a chaque fonctionnalite.

import Cocoa
import Network

class MainWindowController: NSWindowController {

    private var connectionLabel: NSTextField!
    private var connectionDot: NSView!
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "MainWindowMonitor")

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mon Réseau"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 420, height: 360)

        self.init(window: window)
        setupUI()
        startMonitoring()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        // Conteneur principal avec scroll pour redimensionnement
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 20
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
        ])

        // Titre + indicateur de connexion
        let headerStack = NSStackView()
        headerStack.orientation = .horizontal
        headerStack.spacing = 8
        headerStack.alignment = .centerY

        connectionDot = NSView()
        connectionDot.wantsLayer = true
        connectionDot.layer?.cornerRadius = 6
        connectionDot.layer?.backgroundColor = NSColor.systemGray.cgColor
        connectionDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            connectionDot.widthAnchor.constraint(equalToConstant: 12),
            connectionDot.heightAnchor.constraint(equalToConstant: 12),
        ])

        connectionLabel = NSTextField(labelWithString: "Vérification…")
        connectionLabel.font = NSFont.systemFont(ofSize: 13)
        connectionLabel.textColor = .secondaryLabelColor

        let titleLabel = NSTextField(labelWithString: "Mon Réseau")
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)

        headerStack.addArrangedSubview(connectionDot)
        headerStack.addArrangedSubview(connectionLabel)

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(headerStack)

        // Grille de boutons
        let items: [(String, String, Selector)] = [
            ("Détails réseau", "network", #selector(openDetails)),
            ("Qualité réseau", "chart.bar.fill", #selector(openQuality)),
            ("Test de débit", "speedometer", #selector(openSpeedTest)),
            ("Traceroute", "point.topleft.down.to.point.bottomright.curvepath.fill", #selector(openTraceroute)),
            ("DNS", "magnifyingglass", #selector(openDNS)),
            ("WiFi", "wifi", #selector(openWiFi)),
            ("Voisinage", "desktopcomputer", #selector(openNeighborhood)),
        ]

        // 2 colonnes
        let gridStack = NSStackView()
        gridStack.orientation = .vertical
        gridStack.spacing = 12
        gridStack.translatesAutoresizingMaskIntoConstraints = false

        var row: NSStackView?
        for (i, item) in items.enumerated() {
            if i % 2 == 0 {
                row = NSStackView()
                row!.orientation = .horizontal
                row!.spacing = 12
                row!.distribution = .fillEqually
                gridStack.addArrangedSubview(row!)
                row!.translatesAutoresizingMaskIntoConstraints = false
                row!.widthAnchor.constraint(equalTo: gridStack.widthAnchor).isActive = true
            }
            let card = makeCard(title: item.0, symbolName: item.1, action: item.2)
            row?.addArrangedSubview(card)
        }

        // Si nombre impair, ajouter un espace vide
        if items.count % 2 != 0 {
            let spacer = NSView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            row?.addArrangedSubview(spacer)
        }

        stack.addArrangedSubview(gridStack)
        gridStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func makeCard(title: String, symbolName: String, action: Selector) -> NSView {
        let button = NSButton()
        button.title = ""
        button.bezelStyle = .rounded
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 10
        button.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor.separatorColor.cgColor
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false

        let cardStack = NSStackView()
        cardStack.orientation = .vertical
        cardStack.spacing = 6
        cardStack.alignment = .centerX
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        cardStack.isHidden = false

        // Icone SF Symbol
        let imageView = NSImageView()
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) {
            let config = NSImage.SymbolConfiguration(pointSize: 24, weight: .medium)
            imageView.image = img.withSymbolConfiguration(config)
        }
        imageView.contentTintColor = .controlAccentColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 32),
            imageView.heightAnchor.constraint(equalToConstant: 32),
        ])

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.alignment = .center

        cardStack.addArrangedSubview(imageView)
        cardStack.addArrangedSubview(label)

        // Mettre le stack dans le bouton
        button.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            cardStack.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            button.heightAnchor.constraint(equalToConstant: 80),
        ])

        // Tracking area pour effet hover
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: button,
            userInfo: ["button": button]
        )
        button.addTrackingArea(trackingArea)

        return button
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let connected = path.status == .satisfied
                self?.connectionDot.layer?.backgroundColor = (connected ? NSColor.systemGreen : NSColor.systemRed).cgColor
                self?.connectionLabel.stringValue = connected ? "Connecté" : "Déconnecté"
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Actions (delegate vers AppDelegate)

    private var appDelegate: AppDelegate? {
        NSApp.delegate as? AppDelegate
    }

    @objc private func openDetails() { appDelegate?.performShowDetails() }
    @objc private func openQuality() { appDelegate?.performShowQuality() }
    @objc private func openSpeedTest() { appDelegate?.performShowSpeedTest() }
    @objc private func openTraceroute() { appDelegate?.performShowTraceroute() }
    @objc private func openDNS() { appDelegate?.performShowDNS() }
    @objc private func openWiFi() { appDelegate?.performShowWiFi() }
    @objc private func openNeighborhood() { appDelegate?.performShowNeighborhood() }

    override func close() {
        monitor.cancel()
        super.close()
    }

    deinit {
        monitor.cancel()
    }
}

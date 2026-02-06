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
    private var gridStack: NSStackView!
    private var sections: [(title: String, cards: [(view: NSView, isGeek: Bool)])] = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("main.title", comment: "")
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 400)

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

        connectionLabel = NSTextField(labelWithString: NSLocalizedString("main.checking", comment: ""))
        connectionLabel.font = NSFont.systemFont(ofSize: 13)
        connectionLabel.textColor = .secondaryLabelColor

        let titleLabel = NSTextField(labelWithString: NSLocalizedString("main.title", comment: ""))
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)

        headerStack.addArrangedSubview(connectionDot)
        headerStack.addArrangedSubview(connectionLabel)

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(headerStack)

        // Grille de boutons organisée par catégorie : (titre, icône, action, geek?)
        let categorizedItems: [(category: String, items: [(String, String, Selector, Bool)])] = [
            (NSLocalizedString("main.category.mesures", comment: ""), [
                (NSLocalizedString("main.card.speedtest", comment: ""), "speedometer", #selector(openSpeedTest), true),
                (NSLocalizedString("main.card.quality", comment: ""), "chart.bar.fill", #selector(openQuality), true),
                (NSLocalizedString("main.card.bandwidth", comment: ""), "arrow.up.arrow.down", #selector(openBandwidth), true),
                (NSLocalizedString("main.card.wifi", comment: ""), "wifi", #selector(openWiFi), true),
                (NSLocalizedString("main.card.multiping", comment: ""), "arrow.triangle.branch", #selector(openMultiPing), true),
            ]),
            (NSLocalizedString("main.category.information", comment: ""), [
                (NSLocalizedString("main.card.details", comment: ""), "network", #selector(openDetails), true),
                (NSLocalizedString("main.card.dns", comment: ""), "magnifyingglass", #selector(openDNS), true),
                (NSLocalizedString("main.card.whois", comment: ""), "globe.desk", #selector(openWhois), true),
                (NSLocalizedString("main.card.neighborhood", comment: ""), "desktopcomputer", #selector(openNeighborhood), true),
            ]),
            (NSLocalizedString("main.category.diagnostic", comment: ""), [
                (NSLocalizedString("main.card.traceroute", comment: ""), "point.topleft.down.to.point.bottomright.curvepath.fill", #selector(openTraceroute), true),
                (NSLocalizedString("main.card.mtr", comment: ""), "point.3.connected.trianglepath.dotted", #selector(openMTR), true),
                (NSLocalizedString("main.card.httptest", comment: ""), "globe.badge.chevron.backward", #selector(openHTTPTest), true),
                (NSLocalizedString("main.card.ssl", comment: ""), "lock.shield.fill", #selector(openSSLInspector), true),
                (NSLocalizedString("main.card.wol", comment: ""), "power", #selector(openWakeOnLAN), true),
            ]),
            (NSLocalizedString("main.category.surveillance", comment: ""), [
                (NSLocalizedString("main.card.dashboard", comment: ""), "rectangle.3.group.fill", #selector(openDashboard), false),
                (NSLocalizedString("main.card.reports", comment: ""), "chart.bar.doc.horizontal.fill", #selector(openReports), true),
                (NSLocalizedString("main.card.teletravail", comment: ""), "person.and.arrow.left.and.arrow.right", #selector(openTeletravail), false),
            ]),
            ("", [
                (NSLocalizedString("main.card.guide", comment: ""), "book.fill", #selector(openGuide), false),
                (NSLocalizedString("main.card.settings", comment: ""), "gearshape.fill", #selector(openSettings), false),
            ]),
        ]

        // 2 colonnes
        gridStack = NSStackView()
        gridStack.orientation = .vertical
        gridStack.spacing = 8
        gridStack.translatesAutoresizingMaskIntoConstraints = false

        sections = categorizedItems.map { section in
            let cards = section.items.map { (makeCard(title: $0.0, symbolName: $0.1, action: $0.2), $0.3) }
            return (title: section.category, cards: cards)
        }

        stack.addArrangedSubview(gridStack)
        gridStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        NotificationCenter.default.addObserver(self, selector: #selector(updateGeekModeGrid), name: Notification.Name("GeekModeChanged"), object: nil)
        updateGeekModeGrid()
    }

    private func makeCard(title: String, symbolName: String, action: Selector) -> NSView {
        let button = ThemedCardButton()
        button.target = self
        button.action = action
        button.setAccessibilityLabel(title)
        button.setAccessibilityRole(.button)
        button.translatesAutoresizingMaskIntoConstraints = false

        let cardStack = NSStackView()
        cardStack.orientation = .vertical
        cardStack.spacing = 3
        cardStack.alignment = .centerX
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        cardStack.isHidden = false

        // Icone SF Symbol
        let imageView = NSImageView()
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            imageView.image = img.withSymbolConfiguration(config)
        }
        imageView.contentTintColor = .controlAccentColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 20),
            imageView.heightAnchor.constraint(equalToConstant: 20),
        ])

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        label.alignment = .center

        cardStack.addArrangedSubview(imageView)
        cardStack.addArrangedSubview(label)

        // Mettre le stack dans le bouton
        button.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            cardStack.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            button.heightAnchor.constraint(equalToConstant: 48),
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

    private func makeSectionHeader(title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    @objc private func updateGeekModeGrid() {
        let geekMode = UserDefaults.standard.bool(forKey: "GeekMode")

        // Retirer les anciennes lignes
        for view in gridStack.arrangedSubviews {
            gridStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        // Reconstruire par section
        for section in sections {
            let visibleCards = section.cards.filter { !$0.isGeek || geekMode }.map(\.view)
            guard !visibleCards.isEmpty else { continue }

            // En-tête de section (sauf pour la dernière section sans titre)
            if !section.title.isEmpty {
                let header = makeSectionHeader(title: section.title)
                gridStack.addArrangedSubview(header)
                header.leadingAnchor.constraint(equalTo: gridStack.leadingAnchor).isActive = true
            }

            // Cartes en lignes de 5
            let columns = 5
            var row: NSStackView?
            for (i, card) in visibleCards.enumerated() {
                if i % columns == 0 {
                    row = NSStackView()
                    row!.orientation = .horizontal
                    row!.spacing = 8
                    row!.distribution = .fillEqually
                    gridStack.addArrangedSubview(row!)
                    row!.translatesAutoresizingMaskIntoConstraints = false
                    row!.widthAnchor.constraint(equalTo: gridStack.widthAnchor).isActive = true
                }
                row?.addArrangedSubview(card)
            }
            let remainder = visibleCards.count % columns
            if remainder != 0 {
                for _ in 0..<(columns - remainder) {
                    let spacer = NSView()
                    spacer.translatesAutoresizingMaskIntoConstraints = false
                    row?.addArrangedSubview(spacer)
                }
            }
        }

        // Ajuster la taille de la fenêtre au contenu
        if let window = self.window, let contentView = window.contentView {
            contentView.layoutSubtreeIfNeeded()
            let fittingSize = contentView.fittingSize
            let newHeight = max(fittingSize.height + 20, 200)
            var frame = window.frame
            let delta = newHeight - frame.height
            frame.origin.y -= delta
            frame.size.height = newHeight
            frame.size.width = max(frame.size.width, 600)
            window.setFrame(frame, display: true, animate: true)
        }
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let connected = path.status == .satisfied
                self?.connectionDot.layer?.backgroundColor = (connected ? NSColor.systemGreen : NSColor.systemRed).cgColor
                self?.connectionLabel.stringValue = connected ? NSLocalizedString("menu.connected", comment: "") : NSLocalizedString("menu.disconnected", comment: "")
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
    @objc private func openBandwidth() { appDelegate?.performShowBandwidth() }
    @objc private func openWhois() { appDelegate?.performShowWhois() }
    @objc private func openReports() { appDelegate?.performShowReports() }
    @objc private func openTeletravail() { appDelegate?.performShowTeletravail() }
    @objc private func openGuide() { appDelegate?.performShowGuide() }
    @objc private func openSettings() { appDelegate?.performShowSettings() }
    // Nouvelles fonctionnalités avancées
    @objc private func openMTR() { appDelegate?.performShowMTR() }
    @objc private func openMultiPing() { appDelegate?.performShowMultiPing() }
    @objc private func openHTTPTest() { appDelegate?.performShowHTTPTest() }
    @objc private func openSSLInspector() { appDelegate?.performShowSSLInspector() }
    @objc private func openWakeOnLAN() { appDelegate?.performShowWakeOnLAN() }
    @objc private func openDashboard() { appDelegate?.performShowDashboard() }

    override func close() {
        NotificationCenter.default.removeObserver(self)
        monitor.cancel()
        super.close()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        monitor.cancel()
    }
}

// MARK: - Bouton carte adaptatif (apparence)

private class ThemedCardButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        bezelStyle = .rounded
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
}

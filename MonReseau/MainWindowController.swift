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
    private var allCards: [(view: NSView, isGeek: Bool)] = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("main.title", comment: "")
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

        connectionLabel = NSTextField(labelWithString: NSLocalizedString("main.checking", comment: ""))
        connectionLabel.font = NSFont.systemFont(ofSize: 13)
        connectionLabel.textColor = .secondaryLabelColor

        let titleLabel = NSTextField(labelWithString: NSLocalizedString("main.title", comment: ""))
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)

        headerStack.addArrangedSubview(connectionDot)
        headerStack.addArrangedSubview(connectionLabel)

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(headerStack)

        // Grille de boutons : (titre, icône, action, geek?)
        let items: [(String, String, Selector, Bool)] = [
            (NSLocalizedString("main.card.details", comment: ""), "network", #selector(openDetails), true),
            (NSLocalizedString("main.card.quality", comment: ""), "chart.bar.fill", #selector(openQuality), true),
            (NSLocalizedString("main.card.speedtest", comment: ""), "speedometer", #selector(openSpeedTest), true),
            (NSLocalizedString("main.card.traceroute", comment: ""), "point.topleft.down.to.point.bottomright.curvepath.fill", #selector(openTraceroute), true),
            (NSLocalizedString("main.card.dns", comment: ""), "magnifyingglass", #selector(openDNS), true),
            (NSLocalizedString("main.card.wifi", comment: ""), "wifi", #selector(openWiFi), true),
            (NSLocalizedString("main.card.neighborhood", comment: ""), "desktopcomputer", #selector(openNeighborhood), true),
            (NSLocalizedString("main.card.teletravail", comment: ""), "person.and.arrow.left.and.arrow.right", #selector(openTeletravail), false),
            (NSLocalizedString("main.card.guide", comment: ""), "book.fill", #selector(openGuide), false),
            (NSLocalizedString("main.card.settings", comment: ""), "gearshape.fill", #selector(openSettings), false),
        ]

        // 2 colonnes
        gridStack = NSStackView()
        gridStack.orientation = .vertical
        gridStack.spacing = 12
        gridStack.translatesAutoresizingMaskIntoConstraints = false

        allCards = items.map { (makeCard(title: $0.0, symbolName: $0.1, action: $0.2), $0.3) }

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

    @objc private func updateGeekModeGrid() {
        let geekMode = UserDefaults.standard.bool(forKey: "GeekMode")
        let visibleCards = allCards.filter { !$0.isGeek || geekMode }.map(\.view)

        // Retirer les anciennes lignes
        for view in gridStack.arrangedSubviews {
            gridStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        // Reconstruire en lignes de 2
        var row: NSStackView?
        for (i, card) in visibleCards.enumerated() {
            if i % 2 == 0 {
                row = NSStackView()
                row!.orientation = .horizontal
                row!.spacing = 12
                row!.distribution = .fillEqually
                gridStack.addArrangedSubview(row!)
                row!.translatesAutoresizingMaskIntoConstraints = false
                row!.widthAnchor.constraint(equalTo: gridStack.widthAnchor).isActive = true
            }
            row?.addArrangedSubview(card)
        }
        if visibleCards.count % 2 != 0 {
            let spacer = NSView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            row?.addArrangedSubview(spacer)
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
            frame.size.width = max(frame.size.width, 420)
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
    @objc private func openTeletravail() { appDelegate?.performShowTeletravail() }
    @objc private func openGuide() { appDelegate?.performShowGuide() }
    @objc private func openSettings() { appDelegate?.performShowSettings() }

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
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
}

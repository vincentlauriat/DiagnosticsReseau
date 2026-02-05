// GuideWindowController.swift
// NetDisco
//
// Fenêtre de documentation avec présentation split-view :
//   - Panneau gauche (sidebar) : liste des sections avec icônes SF Symbols
//   - Panneau droit : contenu détaillé de la section sélectionnée
// Couvre : présentation de l'app, fonctionnalités, concepts réseau,
// astuces d'optimisation, intégration système et raccourcis clavier.

import Cocoa

// Flipped view pour que le contenu s'affiche depuis le haut
private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

class GuideWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSplitViewDelegate {

    private var splitView: NSSplitView!
    private var sidebarTableView: NSTableView!
    private var detailScrollView: NSScrollView!
    private var detailContainer: FlippedView!

    private struct Section {
        let title: String
        let icon: String
        let content: () -> NSView
    }

    private var sections: [Section] = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 850, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("guide.title", comment: "")
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 650, height: 450)
        self.init(window: window)
        buildSections()
        setupUI()
    }

    // MARK: - Build Sections

    private func buildSections() {
        sections = [
            Section(title: NSLocalizedString("guide.section.about", comment: "À propos"), icon: "info.circle.fill", content: buildAboutSection),
            Section(title: NSLocalizedString("guide.section.tools_basic", comment: "Outils de base"), icon: "network", content: buildBasicToolsSection),
            Section(title: NSLocalizedString("guide.section.tools_advanced", comment: "Outils avancés"), icon: "wrench.and.screwdriver.fill", content: buildAdvancedToolsSection),
            Section(title: NSLocalizedString("guide.section.monitoring", comment: "Surveillance"), icon: "gauge.with.dots.needle.bottom.50percent", content: buildMonitoringSection),
            Section(title: NSLocalizedString("guide.section.concepts", comment: "Concepts réseau"), icon: "book.fill", content: buildConceptsSection),
            Section(title: NSLocalizedString("guide.section.tips", comment: "Astuces"), icon: "lightbulb.fill", content: buildTipsSection),
            Section(title: NSLocalizedString("guide.section.teletravail", comment: "Télétravail"), icon: "house.fill", content: buildTeletravailSection),
            Section(title: NSLocalizedString("guide.section.integration", comment: "Intégration système"), icon: "gearshape.2.fill", content: buildIntegrationSection),
            Section(title: NSLocalizedString("guide.section.shortcuts", comment: "Raccourcis"), icon: "command", content: buildShortcutsSection),
        ]
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // --- Split View ---
        splitView = NSSplitView()
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        contentView.addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: contentView.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        // --- Sidebar (left) ---
        let sidebarScroll = NSScrollView()
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.autohidesScrollers = true
        sidebarScroll.borderType = .noBorder
        sidebarScroll.autoresizingMask = [.width, .height]

        sidebarTableView = NSTableView()
        sidebarTableView.headerView = nil
        sidebarTableView.style = .sourceList
        sidebarTableView.rowHeight = 32
        sidebarTableView.dataSource = self
        sidebarTableView.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Section"))
        column.title = ""
        sidebarTableView.addTableColumn(column)

        sidebarScroll.documentView = sidebarTableView
        splitView.addSubview(sidebarScroll)

        // --- Detail (right) ---
        let rightPane = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        rightPane.autoresizingMask = [.width, .height]

        detailScrollView = NSScrollView()
        detailScrollView.translatesAutoresizingMaskIntoConstraints = false
        detailScrollView.hasVerticalScroller = true
        detailScrollView.autohidesScrollers = true
        detailScrollView.borderType = .noBorder
        detailScrollView.drawsBackground = false
        rightPane.addSubview(detailScrollView)

        NSLayoutConstraint.activate([
            detailScrollView.topAnchor.constraint(equalTo: rightPane.topAnchor),
            detailScrollView.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor),
            detailScrollView.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor),
            detailScrollView.bottomAnchor.constraint(equalTo: rightPane.bottomAnchor),
        ])

        splitView.addSubview(rightPane)

        // Position the divider after layout
        DispatchQueue.main.async {
            self.splitView.setPosition(220, ofDividerAt: 0)
        }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if sidebarTableView.selectedRow < 0 && sections.count > 0 {
            sidebarTableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            showDetail(for: 0)
        }
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellId = NSUserInterfaceItemIdentifier("SectionCell")
        let cell: NSTableCellView
        if let existing = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTableCellView {
            cell = existing
        } else {
            cell = NSTableCellView()
            cell.identifier = cellId

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imageView)
            cell.imageView = imageView

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.font = NSFont.systemFont(ofSize: 13)
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 20),
                imageView.heightAnchor.constraint(equalToConstant: 20),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        let section = sections[row]
        cell.textField?.stringValue = section.title
        if let img = NSImage(systemSymbolName: section.icon, accessibilityDescription: section.title) {
            cell.imageView?.image = img
            cell.imageView?.contentTintColor = .controlAccentColor
        }

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = sidebarTableView.selectedRow
        if row >= 0 && row < sections.count {
            showDetail(for: row)
        }
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return 180
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return 300
    }

    // MARK: - Detail Display

    private func showDetail(for row: Int) {
        let section = sections[row]
        let contentStack = section.content()

        // Créer un container flipped pour affichage depuis le haut
        let container = FlippedView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Configurer le stack principal
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentStack)

        // Contraintes du stack dans le container
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -24),
        ])

        detailScrollView.documentView = container

        // Contrainte de largeur pour que le container suive la scroll view
        let clipView = detailScrollView.contentView
        container.widthAnchor.constraint(equalTo: clipView.widthAnchor).isActive = true

        // Scroll en haut
        DispatchQueue.main.async {
            self.detailScrollView.documentView?.scroll(.zero)
        }
    }

    // MARK: - Section Builders

    private func buildAboutSection() -> NSView {
        let stack = createStack()

        addSectionTitle(NSLocalizedString("guide.about.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.about.intro", comment: ""), to: stack)

        addSubTitle(NSLocalizedString("guide.about.features.title", comment: "Fonctionnalités principales"), to: stack)

        let features: [(String, String, String)] = [
            ("network", NSLocalizedString("guide.feature.details", comment: "Détails réseau"), NSLocalizedString("guide.feature.details.desc", comment: "")),
            ("waveform.path.ecg", NSLocalizedString("guide.feature.quality", comment: "Qualité réseau"), NSLocalizedString("guide.feature.quality.desc", comment: "")),
            ("speedometer", NSLocalizedString("guide.feature.speedtest", comment: "Test de débit"), NSLocalizedString("guide.feature.speedtest.desc", comment: "")),
            ("wifi", NSLocalizedString("guide.feature.wifi", comment: "WiFi"), NSLocalizedString("guide.feature.wifi.desc", comment: "")),
            ("point.3.connected.trianglepath.dotted", NSLocalizedString("guide.feature.traceroute", comment: "Traceroute"), NSLocalizedString("guide.feature.traceroute.desc", comment: "")),
            ("text.magnifyingglass", NSLocalizedString("guide.feature.dns", comment: "DNS"), NSLocalizedString("guide.feature.dns.desc", comment: "")),
            ("externaldrive.connected.to.line.below", NSLocalizedString("guide.feature.neighborhood", comment: "Voisinage réseau"), NSLocalizedString("guide.feature.neighborhood.desc", comment: "")),
            ("chart.bar.fill", NSLocalizedString("guide.feature.bandwidth", comment: "Bande passante"), NSLocalizedString("guide.feature.bandwidth.desc", comment: "")),
            ("globe", NSLocalizedString("guide.feature.whois", comment: "WHOIS"), NSLocalizedString("guide.feature.whois.desc", comment: "")),
            ("house.fill", NSLocalizedString("guide.feature.teletravail", comment: "Télétravail"), NSLocalizedString("guide.feature.teletravail.desc", comment: "")),
        ]

        for (icon, title, desc) in features {
            addFeatureRow(icon: icon, title: title, description: desc, to: stack)
        }

        addSpacer(to: stack)

        addSubTitle(NSLocalizedString("guide.about.geekmode.title", comment: "Mode Geek"), to: stack)
        addParagraph(NSLocalizedString("guide.about.geekmode.desc", comment: ""), to: stack)

        addSubTitle(NSLocalizedString("guide.about.modes.title", comment: "Modes d'affichage"), to: stack)
        addParagraph(NSLocalizedString("guide.about.modes.desc", comment: ""), to: stack)

        return stack
    }

    private func buildBasicToolsSection() -> NSView {
        let stack = createStack()

        addSectionTitle(NSLocalizedString("guide.tools.basic.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.tools.basic.intro", comment: ""), to: stack)

        // Détails réseau
        addToolCard(
            icon: "network",
            title: NSLocalizedString("guide.tool.details.title", comment: ""),
            description: NSLocalizedString("guide.tool.details.desc", comment: ""),
            features: [
                NSLocalizedString("guide.tool.details.feature1", comment: ""),
                NSLocalizedString("guide.tool.details.feature2", comment: ""),
                NSLocalizedString("guide.tool.details.feature3", comment: ""),
                NSLocalizedString("guide.tool.details.feature4", comment: ""),
            ],
            to: stack
        )

        // Qualité réseau
        addToolCard(
            icon: "waveform.path.ecg",
            title: NSLocalizedString("guide.tool.quality.title", comment: ""),
            description: NSLocalizedString("guide.tool.quality.desc", comment: ""),
            features: [
                NSLocalizedString("guide.tool.quality.feature1", comment: ""),
                NSLocalizedString("guide.tool.quality.feature2", comment: ""),
                NSLocalizedString("guide.tool.quality.feature3", comment: ""),
            ],
            to: stack
        )

        // Test de débit
        addToolCard(
            icon: "speedometer",
            title: NSLocalizedString("guide.tool.speedtest.title", comment: ""),
            description: NSLocalizedString("guide.tool.speedtest.desc", comment: ""),
            features: [
                NSLocalizedString("guide.tool.speedtest.feature1", comment: ""),
                NSLocalizedString("guide.tool.speedtest.feature2", comment: ""),
                NSLocalizedString("guide.tool.speedtest.feature3", comment: ""),
            ],
            to: stack
        )

        // WiFi
        addToolCard(
            icon: "wifi",
            title: NSLocalizedString("guide.tool.wifi.title", comment: ""),
            description: NSLocalizedString("guide.tool.wifi.desc", comment: ""),
            features: [
                NSLocalizedString("guide.tool.wifi.feature1", comment: ""),
                NSLocalizedString("guide.tool.wifi.feature2", comment: ""),
                NSLocalizedString("guide.tool.wifi.feature3", comment: ""),
            ],
            to: stack
        )

        return stack
    }

    private func buildAdvancedToolsSection() -> NSView {
        let stack = createStack()

        addSectionTitle(NSLocalizedString("guide.tools.advanced.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.tools.advanced.intro", comment: ""), to: stack)

        // MTR
        addToolCard(
            icon: "point.3.filled.connected.trianglepath.dotted",
            title: NSLocalizedString("guide.tool.mtr.title", comment: ""),
            description: NSLocalizedString("guide.tool.mtr.desc", comment: ""),
            features: [
                NSLocalizedString("guide.tool.mtr.feature1", comment: ""),
                NSLocalizedString("guide.tool.mtr.feature2", comment: ""),
                NSLocalizedString("guide.tool.mtr.feature3", comment: ""),
            ],
            to: stack
        )

        // Multi-ping
        addToolCard(
            icon: "chart.line.uptrend.xyaxis",
            title: NSLocalizedString("guide.tool.multiping.title", comment: ""),
            description: NSLocalizedString("guide.tool.multiping.desc", comment: ""),
            features: [
                NSLocalizedString("guide.tool.multiping.feature1", comment: ""),
                NSLocalizedString("guide.tool.multiping.feature2", comment: ""),
            ],
            to: stack
        )

        // Traceroute
        addToolCard(
            icon: "point.3.connected.trianglepath.dotted",
            title: NSLocalizedString("guide.tool.traceroute.title", comment: ""),
            description: NSLocalizedString("guide.tool.traceroute.desc", comment: ""),
            features: [
                NSLocalizedString("guide.tool.traceroute.feature1", comment: ""),
                NSLocalizedString("guide.tool.traceroute.feature2", comment: ""),
                NSLocalizedString("guide.tool.traceroute.feature3", comment: ""),
            ],
            to: stack
        )

        // DNS
        addToolCard(
            icon: "text.magnifyingglass",
            title: NSLocalizedString("guide.tool.dns.title", comment: ""),
            description: NSLocalizedString("guide.tool.dns.desc", comment: ""),
            features: [
                NSLocalizedString("guide.tool.dns.feature1", comment: ""),
                NSLocalizedString("guide.tool.dns.feature2", comment: ""),
                NSLocalizedString("guide.tool.dns.feature3", comment: ""),
            ],
            to: stack
        )

        // WHOIS
        addToolCard(
            icon: "globe",
            title: NSLocalizedString("guide.tool.whois.title", comment: ""),
            description: NSLocalizedString("guide.tool.whois.desc", comment: ""),
            features: [
                NSLocalizedString("guide.tool.whois.feature1", comment: ""),
                NSLocalizedString("guide.tool.whois.feature2", comment: ""),
            ],
            to: stack
        )

        // HTTP Test
        addToolCard(
            icon: "globe.badge.chevron.backward",
            title: NSLocalizedString("guide.tool.http.title", comment: ""),
            description: NSLocalizedString("guide.tool.http.desc", comment: ""),
            features: [
                NSLocalizedString("guide.tool.http.feature1", comment: ""),
                NSLocalizedString("guide.tool.http.feature2", comment: ""),
            ],
            to: stack
        )

        // SSL Inspector
        addToolCard(
            icon: "lock.shield",
            title: NSLocalizedString("guide.tool.ssl.title", comment: ""),
            description: NSLocalizedString("guide.tool.ssl.desc", comment: ""),
            features: [
                NSLocalizedString("guide.tool.ssl.feature1", comment: ""),
                NSLocalizedString("guide.tool.ssl.feature2", comment: ""),
            ],
            to: stack
        )

        // Voisinage réseau
        addToolCard(
            icon: "externaldrive.connected.to.line.below",
            title: NSLocalizedString("guide.tool.neighborhood.title", comment: ""),
            description: NSLocalizedString("guide.tool.neighborhood.desc", comment: ""),
            features: [
                NSLocalizedString("guide.tool.neighborhood.feature1", comment: ""),
                NSLocalizedString("guide.tool.neighborhood.feature2", comment: ""),
                NSLocalizedString("guide.tool.neighborhood.feature3", comment: ""),
            ],
            to: stack
        )

        // Wake on LAN
        addToolCard(
            icon: "power",
            title: NSLocalizedString("guide.tool.wol.title", comment: ""),
            description: NSLocalizedString("guide.tool.wol.desc", comment: ""),
            features: [
                NSLocalizedString("guide.tool.wol.feature1", comment: ""),
                NSLocalizedString("guide.tool.wol.feature2", comment: ""),
            ],
            to: stack
        )

        // Bande passante
        addToolCard(
            icon: "chart.bar.fill",
            title: NSLocalizedString("guide.tool.bandwidth.title", comment: ""),
            description: NSLocalizedString("guide.tool.bandwidth.desc", comment: ""),
            features: [
                NSLocalizedString("guide.tool.bandwidth.feature1", comment: ""),
                NSLocalizedString("guide.tool.bandwidth.feature2", comment: ""),
            ],
            to: stack
        )

        return stack
    }

    private func buildMonitoringSection() -> NSView {
        let stack = createStack()

        addSectionTitle(NSLocalizedString("guide.monitoring.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.monitoring.intro", comment: ""), to: stack)

        // Dashboard
        addToolCard(
            icon: "gauge.with.dots.needle.bottom.50percent",
            title: NSLocalizedString("guide.tool.dashboard.title", comment: ""),
            description: NSLocalizedString("guide.tool.dashboard.desc", comment: ""),
            features: [
                NSLocalizedString("guide.tool.dashboard.feature1", comment: ""),
                NSLocalizedString("guide.tool.dashboard.feature2", comment: ""),
                NSLocalizedString("guide.tool.dashboard.feature3", comment: ""),
            ],
            to: stack
        )

        // Détection IP
        addToolCard(
            icon: "network.badge.shield.half.filled",
            title: NSLocalizedString("guide.tool.ipchange.title", comment: ""),
            description: NSLocalizedString("guide.tool.ipchange.desc", comment: ""),
            features: [
                NSLocalizedString("guide.tool.ipchange.feature1", comment: ""),
                NSLocalizedString("guide.tool.ipchange.feature2", comment: ""),
            ],
            to: stack
        )

        // Tests planifiés
        addToolCard(
            icon: "clock.arrow.circlepath",
            title: NSLocalizedString("guide.tool.scheduled.title", comment: ""),
            description: NSLocalizedString("guide.tool.scheduled.desc", comment: ""),
            features: [
                NSLocalizedString("guide.tool.scheduled.feature1", comment: ""),
                NSLocalizedString("guide.tool.scheduled.feature2", comment: ""),
                NSLocalizedString("guide.tool.scheduled.feature3", comment: ""),
            ],
            to: stack
        )

        // Auto Analyzer
        addToolCard(
            icon: "wand.and.stars",
            title: NSLocalizedString("guide.tool.analyzer.title", comment: ""),
            description: NSLocalizedString("guide.tool.analyzer.desc", comment: ""),
            features: [
                NSLocalizedString("guide.tool.analyzer.feature1", comment: ""),
                NSLocalizedString("guide.tool.analyzer.feature2", comment: ""),
            ],
            to: stack
        )

        // Profils réseau
        addToolCard(
            icon: "wifi.router",
            title: NSLocalizedString("guide.tool.profiles.title", comment: ""),
            description: NSLocalizedString("guide.tool.profiles.desc", comment: ""),
            features: [
                NSLocalizedString("guide.tool.profiles.feature1", comment: ""),
                NSLocalizedString("guide.tool.profiles.feature2", comment: ""),
            ],
            to: stack
        )

        return stack
    }

    private func buildConceptsSection() -> NSView {
        let stack = createStack()

        addSectionTitle(NSLocalizedString("guide.concepts.title", comment: ""), to: stack)

        let concepts: [(String, String, String)] = [
            ("clock", NSLocalizedString("guide.concepts.latency.title", comment: ""), NSLocalizedString("guide.concepts.latency.text", comment: "")),
            ("waveform.path", NSLocalizedString("guide.concepts.jitter.title", comment: ""), NSLocalizedString("guide.concepts.jitter.text", comment: "")),
            ("exclamationmark.triangle", NSLocalizedString("guide.concepts.loss.title", comment: ""), NSLocalizedString("guide.concepts.loss.text", comment: "")),
            ("speedometer", NSLocalizedString("guide.concepts.speed.title", comment: ""), NSLocalizedString("guide.concepts.speed.text", comment: "")),
            ("text.magnifyingglass", NSLocalizedString("guide.concepts.dns.title", comment: ""), NSLocalizedString("guide.concepts.dns.text", comment: "")),
            ("point.3.connected.trianglepath.dotted", NSLocalizedString("guide.concepts.traceroute.title", comment: ""), NSLocalizedString("guide.concepts.traceroute.text", comment: "")),
            ("wifi", NSLocalizedString("guide.concepts.rssi.title", comment: ""), NSLocalizedString("guide.concepts.rssi.text", comment: "")),
            ("arrow.left.arrow.right", NSLocalizedString("guide.concepts.nat.title", comment: ""), NSLocalizedString("guide.concepts.nat.text", comment: "")),
            ("number", NSLocalizedString("guide.concepts.ipv.title", comment: ""), NSLocalizedString("guide.concepts.ipv.text", comment: "")),
        ]

        for (icon, title, desc) in concepts {
            addConceptCard(icon: icon, title: title, description: desc, to: stack)
        }

        return stack
    }

    private func buildTipsSection() -> NSView {
        let stack = createStack()

        addSectionTitle(NSLocalizedString("guide.tips.title", comment: ""), to: stack)

        let tips: [(String, String, String)] = [
            ("wifi.router", NSLocalizedString("guide.tips.router.title", comment: ""), NSLocalizedString("guide.tips.router.text", comment: "")),
            ("cable.connector", NSLocalizedString("guide.tips.ethernet.title", comment: ""), NSLocalizedString("guide.tips.ethernet.text", comment: "")),
            ("antenna.radiowaves.left.and.right", NSLocalizedString("guide.tips.channel.title", comment: ""), NSLocalizedString("guide.tips.channel.text", comment: "")),
            ("arrow.clockwise", NSLocalizedString("guide.tips.reboot.title", comment: ""), NSLocalizedString("guide.tips.reboot.text", comment: "")),
            ("person.3.fill", NSLocalizedString("guide.tips.bandwidth.title", comment: ""), NSLocalizedString("guide.tips.bandwidth.text", comment: "")),
            ("arrow.down.to.line", NSLocalizedString("guide.tips.install.title", comment: ""), NSLocalizedString("guide.tips.install.text", comment: "")),
        ]

        for (icon, title, desc) in tips {
            addTipCard(icon: icon, title: title, description: desc, to: stack)
        }

        addSpacer(to: stack)

        // DNS Tips
        addSubTitle(NSLocalizedString("guide.tips.dns.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.tips.dns.text", comment: ""), to: stack)

        let dnsGrid = NSGridView(numberOfColumns: 2, rows: 0)
        dnsGrid.translatesAutoresizingMaskIntoConstraints = false
        dnsGrid.columnSpacing = 16
        dnsGrid.rowSpacing = 6

        let dnsServers: [(String, String)] = [
            ("Cloudflare", "1.1.1.1 / 1.0.0.1"),
            ("Google", "8.8.8.8 / 8.8.4.4"),
            ("Quad9", "9.9.9.9 / 149.112.112.112"),
            ("OpenDNS", "208.67.222.222 / 208.67.220.220"),
        ]

        for (name, ips) in dnsServers {
            let nameLabel = NSTextField(labelWithString: name)
            nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            let ipsLabel = NSTextField(labelWithString: ips)
            ipsLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            ipsLabel.textColor = .secondaryLabelColor
            dnsGrid.addRow(with: [nameLabel, ipsLabel])
        }

        stack.addArrangedSubview(dnsGrid)

        addParagraph(NSLocalizedString("guide.tips.dns.outro", comment: ""), to: stack)

        return stack
    }

    private func buildTeletravailSection() -> NSView {
        let stack = createStack()

        addSectionTitle(NSLocalizedString("guide.teletravail.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.teletravail.intro", comment: ""), to: stack)

        // Tableau des seuils par usage
        let usageGrid = NSGridView(numberOfColumns: 6, rows: 0)
        usageGrid.translatesAutoresizingMaskIntoConstraints = false
        usageGrid.columnSpacing = 10
        usageGrid.rowSpacing = 6

        // En-têtes
        let headers = [
            NSLocalizedString("guide.teletravail.header.usage", comment: ""),
            NSLocalizedString("guide.teletravail.header.download", comment: ""),
            NSLocalizedString("guide.teletravail.header.upload", comment: ""),
            NSLocalizedString("guide.teletravail.header.latency", comment: ""),
            NSLocalizedString("guide.teletravail.header.jitter", comment: ""),
            NSLocalizedString("guide.teletravail.header.loss", comment: ""),
        ]
        let headerViews = headers.map { text -> NSTextField in
            let l = NSTextField(labelWithString: text)
            l.font = NSFont.systemFont(ofSize: 11, weight: .bold)
            l.textColor = .controlAccentColor
            return l
        }
        usageGrid.addRow(with: headerViews)

        // Données
        let usageData: [(String, String, String, String, String, String)] = [
            (NSLocalizedString("guide.teletravail.usage.visio", comment: ""), "5", "3", "100", "30", "2"),
            (NSLocalizedString("guide.teletravail.usage.visiohd", comment: ""), "15", "8", "50", "20", "1"),
            (NSLocalizedString("guide.teletravail.usage.email", comment: ""), "1", "0.5", "300", "100", "5"),
            (NSLocalizedString("guide.teletravail.usage.citrix", comment: ""), "5", "2", "80", "20", "1"),
            (NSLocalizedString("guide.teletravail.usage.transfer", comment: ""), "10", "5", "500", "100", "3"),
            (NSLocalizedString("guide.teletravail.usage.streaming", comment: ""), "25", "1", "200", "50", "2"),
            (NSLocalizedString("guide.teletravail.usage.gaming", comment: ""), "25", "5", "30", "10", "0.5"),
        ]

        for (name, dl, ul, lat, jit, loss) in usageData {
            let views = [name, "≥ \(dl)", "≥ \(ul)", "≤ \(lat)", "≤ \(jit)", "≤ \(loss)"].map { text -> NSTextField in
                let l = NSTextField(labelWithString: text)
                l.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                return l
            }
            views[0].font = NSFont.systemFont(ofSize: 12)
            usageGrid.addRow(with: views)
        }

        let gridContainer = NSView()
        gridContainer.translatesAutoresizingMaskIntoConstraints = false
        gridContainer.addSubview(usageGrid)
        NSLayoutConstraint.activate([
            usageGrid.topAnchor.constraint(equalTo: gridContainer.topAnchor, constant: 8),
            usageGrid.leadingAnchor.constraint(equalTo: gridContainer.leadingAnchor),
            usageGrid.bottomAnchor.constraint(equalTo: gridContainer.bottomAnchor, constant: -8),
        ])
        stack.addArrangedSubview(gridContainer)

        addSpacer(to: stack)

        addSubTitle(NSLocalizedString("guide.teletravail.verdicts.title", comment: "Verdicts"), to: stack)
        addBulletList([
            NSLocalizedString("guide.teletravail.verdict.excellent", comment: ""),
            NSLocalizedString("guide.teletravail.verdict.ok", comment: ""),
            NSLocalizedString("guide.teletravail.verdict.degraded", comment: ""),
            NSLocalizedString("guide.teletravail.verdict.insufficient", comment: ""),
        ], to: stack)

        addSubTitle(NSLocalizedString("guide.teletravail.indicators.title", comment: ""), to: stack)
        addBulletList([
            NSLocalizedString("guide.teletravail.indicator.wifi", comment: ""),
            NSLocalizedString("guide.teletravail.indicator.latency", comment: ""),
            NSLocalizedString("guide.teletravail.indicator.speed", comment: ""),
        ], to: stack)

        addParagraph(NSLocalizedString("guide.teletravail.note", comment: ""), to: stack)

        return stack
    }

    private func buildIntegrationSection() -> NSView {
        let stack = createStack()

        addSectionTitle(NSLocalizedString("guide.integration.title", comment: ""), to: stack)

        // Siri
        addSubTitle(NSLocalizedString("guide.siri.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.siri.intro", comment: ""), to: stack)

        let siriIntents: [(String, String)] = [
            (NSLocalizedString("guide.siri.intent.speedtest", comment: ""), NSLocalizedString("guide.siri.intent.speedtest.desc", comment: "")),
            (NSLocalizedString("guide.siri.intent.details", comment: ""), NSLocalizedString("guide.siri.intent.details.desc", comment: "")),
            (NSLocalizedString("guide.siri.intent.quality", comment: ""), NSLocalizedString("guide.siri.intent.quality.desc", comment: "")),
            (NSLocalizedString("guide.siri.intent.traceroute", comment: ""), NSLocalizedString("guide.siri.intent.traceroute.desc", comment: "")),
            (NSLocalizedString("guide.siri.intent.wifi", comment: ""), NSLocalizedString("guide.siri.intent.wifi.desc", comment: "")),
            (NSLocalizedString("guide.siri.intent.teletravail", comment: ""), NSLocalizedString("guide.siri.intent.teletravail.desc", comment: "")),
            (NSLocalizedString("guide.siri.intent.dns", comment: ""), NSLocalizedString("guide.siri.intent.dns.desc", comment: "")),
            (NSLocalizedString("guide.siri.intent.whois", comment: ""), NSLocalizedString("guide.siri.intent.whois.desc", comment: "")),
        ]

        let siriGrid = NSGridView(numberOfColumns: 2, rows: 0)
        siriGrid.translatesAutoresizingMaskIntoConstraints = false
        siriGrid.columnSpacing = 16
        siriGrid.rowSpacing = 6

        for (intent, desc) in siriIntents {
            let intentLabel = NSTextField(labelWithString: intent)
            intentLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            intentLabel.textColor = .controlAccentColor
            let descLabel = NSTextField(labelWithString: desc)
            descLabel.font = NSFont.systemFont(ofSize: 12)
            descLabel.textColor = .secondaryLabelColor
            siriGrid.addRow(with: [intentLabel, descLabel])
        }

        stack.addArrangedSubview(siriGrid)

        addSpacer(to: stack)

        // Widgets
        addSubTitle(NSLocalizedString("guide.widgets.title", comment: "Widgets"), to: stack)
        addParagraph(NSLocalizedString("guide.widgets.desc", comment: ""), to: stack)

        let widgetTypes: [(String, String)] = [
            (NSLocalizedString("guide.widgets.small", comment: ""), NSLocalizedString("guide.widgets.small.desc", comment: "")),
            (NSLocalizedString("guide.widgets.medium", comment: ""), NSLocalizedString("guide.widgets.medium.desc", comment: "")),
            (NSLocalizedString("guide.widgets.large", comment: ""), NSLocalizedString("guide.widgets.large.desc", comment: "")),
        ]

        for (size, desc) in widgetTypes {
            let container = NSStackView()
            container.orientation = .horizontal
            container.spacing = 8
            container.alignment = .firstBaseline

            let sizeLabel = NSTextField(labelWithString: "•  " + size)
            sizeLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            let descLabel = NSTextField(labelWithString: desc)
            descLabel.font = NSFont.systemFont(ofSize: 12)
            descLabel.textColor = .secondaryLabelColor

            container.addArrangedSubview(sizeLabel)
            container.addArrangedSubview(descLabel)
            stack.addArrangedSubview(container)
        }

        addSpacer(to: stack)

        // iCloud
        addSubTitle(NSLocalizedString("guide.icloud.title", comment: "iCloud"), to: stack)
        addParagraph(NSLocalizedString("guide.icloud.desc", comment: ""), to: stack)

        addSpacer(to: stack)

        // URL Schemes
        addSubTitle(NSLocalizedString("guide.urlscheme.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.urlscheme.intro", comment: ""), to: stack)

        let urlSchemes: [(String, String)] = [
            ("netdisco://speedtest", NSLocalizedString("menu.speedtest", comment: "").replacingOccurrences(of: "…", with: "")),
            ("netdisco://details", NSLocalizedString("menu.details", comment: "").replacingOccurrences(of: "…", with: "")),
            ("netdisco://quality", NSLocalizedString("menu.quality", comment: "").replacingOccurrences(of: "…", with: "")),
            ("netdisco://traceroute", NSLocalizedString("menu.traceroute", comment: "").replacingOccurrences(of: "…", with: "")),
            ("netdisco://dns", NSLocalizedString("menu.dns", comment: "").replacingOccurrences(of: "…", with: "")),
            ("netdisco://wifi", NSLocalizedString("menu.wifi", comment: "").replacingOccurrences(of: "…", with: "")),
            ("netdisco://neighborhood", NSLocalizedString("menu.neighborhood", comment: "").replacingOccurrences(of: "…", with: "")),
            ("netdisco://bandwidth", NSLocalizedString("menu.bandwidth", comment: "").replacingOccurrences(of: "…", with: "")),
            ("netdisco://whois", NSLocalizedString("menu.whois", comment: "").replacingOccurrences(of: "…", with: "")),
            ("netdisco://teletravail", NSLocalizedString("menu.teletravail", comment: "").replacingOccurrences(of: "…", with: "")),
            ("netdisco://mtr", "MTR"),
            ("netdisco://multiping", "Multi-ping"),
            ("netdisco://httptest", "Test HTTP"),
            ("netdisco://ssl", "SSL Inspector"),
            ("netdisco://wol", "Wake on LAN"),
            ("netdisco://dashboard", "Dashboard"),
            ("netdisco://settings", NSLocalizedString("menu.settings", comment: "").replacingOccurrences(of: "…", with: "")),
        ]

        let urlGrid = NSGridView(numberOfColumns: 2, rows: 0)
        urlGrid.translatesAutoresizingMaskIntoConstraints = false
        urlGrid.columnSpacing = 16
        urlGrid.rowSpacing = 4

        for (url, desc) in urlSchemes {
            let urlLabel = NSTextField(labelWithString: url)
            urlLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            urlLabel.textColor = .linkColor
            urlLabel.isSelectable = true
            let descLabel = NSTextField(labelWithString: desc)
            descLabel.font = NSFont.systemFont(ofSize: 12)
            urlGrid.addRow(with: [urlLabel, descLabel])
        }

        stack.addArrangedSubview(urlGrid)

        addParagraph(NSLocalizedString("guide.urlscheme.usage", comment: ""), to: stack)

        return stack
    }

    private func buildShortcutsSection() -> NSView {
        let stack = createStack()

        addSectionTitle(NSLocalizedString("guide.shortcuts.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.shortcuts.intro", comment: ""), to: stack)

        let shortcuts: [(String, String)] = [
            ("D", NSLocalizedString("menu.details", comment: "").replacingOccurrences(of: "…", with: "")),
            ("G", NSLocalizedString("menu.quality", comment: "").replacingOccurrences(of: "…", with: "")),
            ("T", NSLocalizedString("menu.speedtest", comment: "").replacingOccurrences(of: "…", with: "")),
            ("R", NSLocalizedString("menu.traceroute", comment: "").replacingOccurrences(of: "…", with: "")),
            ("N", NSLocalizedString("menu.dns", comment: "").replacingOccurrences(of: "…", with: "")),
            ("W", NSLocalizedString("menu.wifi", comment: "").replacingOccurrences(of: "…", with: "")),
            ("B", NSLocalizedString("menu.neighborhood", comment: "").replacingOccurrences(of: "…", with: "")),
            ("K", NSLocalizedString("menu.bandwidth", comment: "").replacingOccurrences(of: "…", with: "")),
            ("O", NSLocalizedString("menu.whois", comment: "").replacingOccurrences(of: "…", with: "")),
            ("E", NSLocalizedString("menu.teletravail", comment: "").replacingOccurrences(of: "…", with: "")),
            ("M", "MTR"),
            ("P", "Multi-ping"),
            ("L", "Dashboard"),
            ("H", NSLocalizedString("menu.guide", comment: "").replacingOccurrences(of: "…", with: "")),
            (",", NSLocalizedString("menu.settings", comment: "").replacingOccurrences(of: "…", with: "")),
            ("I", NSLocalizedString("menu.about", comment: "").replacingOccurrences(of: "…", with: "")),
            ("Q", NSLocalizedString("menu.quit", comment: "")),
        ]

        let shortcutGrid = NSGridView(numberOfColumns: 2, rows: 0)
        shortcutGrid.translatesAutoresizingMaskIntoConstraints = false
        shortcutGrid.columnSpacing = 16
        shortcutGrid.rowSpacing = 6
        shortcutGrid.column(at: 0).xPlacement = .trailing
        shortcutGrid.column(at: 0).width = 60
        shortcutGrid.column(at: 1).xPlacement = .leading

        for (key, desc) in shortcuts {
            let keyView = createShortcutKeyView(key: key)
            let descLabel = NSTextField(labelWithString: desc)
            descLabel.font = NSFont.systemFont(ofSize: 13)
            shortcutGrid.addRow(with: [keyView, descLabel])
        }

        stack.addArrangedSubview(shortcutGrid)

        addSpacer(to: stack)

        addSubTitle(NSLocalizedString("guide.shortcuts.global.title", comment: "Raccourcis globaux"), to: stack)
        addParagraph(NSLocalizedString("guide.shortcuts.global.desc", comment: ""), to: stack)

        return stack
    }

    // MARK: - UI Helpers

    private func createStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return stack
    }

    private func makeWrappingLabel(_ text: String, font: NSFont = NSFont.systemFont(ofSize: 13)) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isSelectable = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.lineBreakMode = .byWordWrapping
        label.cell?.wraps = true
        label.cell?.isScrollable = false
        return label
    }

    private func addSectionTitle(_ text: String, to stack: NSStackView) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(label)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 4).isActive = true
        stack.addArrangedSubview(spacer)
    }

    private func addSubTitle(_ text: String, to stack: NSStackView) {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        stack.addArrangedSubview(spacer)

        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .controlAccentColor
        label.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(label)
    }

    private func addParagraph(_ text: String, to stack: NSStackView) {
        let label = makeWrappingLabel(text)
        stack.addArrangedSubview(label)
        label.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
    }

    private func addBulletList(_ items: [String], to stack: NSStackView) {
        for item in items {
            let container = NSStackView()
            container.orientation = .horizontal
            container.spacing = 8
            container.alignment = .firstBaseline
            container.translatesAutoresizingMaskIntoConstraints = false

            let bullet = NSTextField(labelWithString: "•")
            bullet.font = NSFont.systemFont(ofSize: 13, weight: .bold)
            bullet.textColor = .controlAccentColor
            bullet.setContentHuggingPriority(.required, for: .horizontal)
            bullet.setContentCompressionResistancePriority(.required, for: .horizontal)

            let label = makeWrappingLabel(item)

            container.addArrangedSubview(bullet)
            container.addArrangedSubview(label)
            stack.addArrangedSubview(container)
            container.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
        }
    }

    private func addSpacer(to stack: NSStackView) {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        stack.addArrangedSubview(spacer)

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let spacer2 = NSView()
        spacer2.translatesAutoresizingMaskIntoConstraints = false
        spacer2.heightAnchor.constraint(equalToConstant: 8).isActive = true
        stack.addArrangedSubview(spacer2)
    }

    private func addFeatureRow(icon: String, title: String, description: String, to stack: NSStackView) {
        let container = NSStackView()
        container.orientation = .horizontal
        container.spacing = 12
        container.alignment = .top
        container.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: title) {
            imageView.image = img
            imageView.contentTintColor = .controlAccentColor
        }
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.widthAnchor.constraint(equalToConstant: 20).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 20).isActive = true

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        let descLabel = makeWrappingLabel(description, font: NSFont.systemFont(ofSize: 12))
        descLabel.textColor = .secondaryLabelColor

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(descLabel)

        container.addArrangedSubview(imageView)
        container.addArrangedSubview(textStack)

        stack.addArrangedSubview(container)
        container.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
    }

    private func addToolCard(icon: String, title: String, description: String, features: [String], to stack: NSStackView) {
        // Container principal avec fond et bordure
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.layer?.borderWidth = 1
        card.layer?.cornerRadius = 10

        // Stack vertical pour le contenu
        let innerStack = NSStackView()
        innerStack.orientation = .vertical
        innerStack.spacing = 6
        innerStack.alignment = .leading
        innerStack.translatesAutoresizingMaskIntoConstraints = false

        // Header avec icône et titre
        let headerStack = NSStackView()
        headerStack.orientation = .horizontal
        headerStack.spacing = 10
        headerStack.alignment = .centerY
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: title) {
            imageView.image = img
            imageView.contentTintColor = .controlAccentColor
        }
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.widthAnchor.constraint(equalToConstant: 24).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        headerStack.addArrangedSubview(imageView)
        headerStack.addArrangedSubview(titleLabel)

        // Description
        let descLabel = makeWrappingLabel(description, font: NSFont.systemFont(ofSize: 12))
        descLabel.textColor = .secondaryLabelColor

        innerStack.addArrangedSubview(headerStack)
        innerStack.addArrangedSubview(descLabel)

        // Features
        for feature in features {
            let featureStack = NSStackView()
            featureStack.orientation = .horizontal
            featureStack.spacing = 6
            featureStack.alignment = .firstBaseline
            featureStack.translatesAutoresizingMaskIntoConstraints = false

            let checkmark = NSTextField(labelWithString: "✓")
            checkmark.font = NSFont.systemFont(ofSize: 11, weight: .bold)
            checkmark.textColor = .systemGreen
            checkmark.setContentHuggingPriority(.required, for: .horizontal)
            checkmark.setContentCompressionResistancePriority(.required, for: .horizontal)

            let featureLabel = makeWrappingLabel(feature, font: NSFont.systemFont(ofSize: 12))

            featureStack.addArrangedSubview(checkmark)
            featureStack.addArrangedSubview(featureLabel)
            innerStack.addArrangedSubview(featureStack)
        }

        // Ajouter innerStack à la carte
        card.addSubview(innerStack)

        NSLayoutConstraint.activate([
            innerStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            innerStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            innerStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            innerStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])

        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Spacer
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 6).isActive = true
        stack.addArrangedSubview(spacer)
    }

    private func addConceptCard(icon: String, title: String, description: String, to stack: NSStackView) {
        let container = NSStackView()
        container.orientation = .horizontal
        container.spacing = 12
        container.alignment = .top
        container.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: title) {
            imageView.image = img
            imageView.contentTintColor = .tertiaryLabelColor
        }
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.widthAnchor.constraint(equalToConstant: 24).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.spacing = 4
        textStack.alignment = .leading
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .controlAccentColor

        let descLabel = makeWrappingLabel(description)

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(descLabel)

        container.addArrangedSubview(imageView)
        container.addArrangedSubview(textStack)

        stack.addArrangedSubview(container)
        container.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true

        // Spacer
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        stack.addArrangedSubview(spacer)
    }

    private func addTipCard(icon: String, title: String, description: String, to stack: NSStackView) {
        // Container principal avec fond et bordure
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.1).cgColor
        card.layer?.borderColor = NSColor.systemYellow.withAlphaComponent(0.3).cgColor
        card.layer?.borderWidth = 1
        card.layer?.cornerRadius = 8

        let innerStack = NSStackView()
        innerStack.orientation = .horizontal
        innerStack.spacing = 12
        innerStack.alignment = .top
        innerStack.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: title) {
            imageView.image = img
            imageView.contentTintColor = .systemOrange
        }
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.widthAnchor.constraint(equalToConstant: 22).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.spacing = 4
        textStack.alignment = .leading
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let descLabel = makeWrappingLabel(description, font: NSFont.systemFont(ofSize: 12))
        descLabel.textColor = .secondaryLabelColor

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(descLabel)

        innerStack.addArrangedSubview(imageView)
        innerStack.addArrangedSubview(textStack)

        card.addSubview(innerStack)

        NSLayoutConstraint.activate([
            innerStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            innerStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            innerStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            innerStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
        ])

        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Spacer
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 6).isActive = true
        stack.addArrangedSubview(spacer)
    }

    private func createShortcutKeyView(key: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let keyBox = NSBox()
        keyBox.boxType = .custom
        keyBox.cornerRadius = 4
        keyBox.fillColor = NSColor.controlBackgroundColor
        keyBox.borderColor = NSColor.separatorColor
        keyBox.borderWidth = 1
        keyBox.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "⌘\(key)")
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center

        keyBox.contentView?.addSubview(label)
        container.addSubview(keyBox)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: keyBox.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: keyBox.centerYAnchor),
            keyBox.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
            keyBox.heightAnchor.constraint(equalToConstant: 22),
            keyBox.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            keyBox.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            keyBox.topAnchor.constraint(equalTo: container.topAnchor),
            keyBox.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }
}

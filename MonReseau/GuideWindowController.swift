// GuideWindowController.swift
// Mon Réseau
//
// Fenêtre de documentation : présentation de l'app, concepts réseau,
// astuces d'optimisation et raccourcis clavier.

import Cocoa

class GuideWindowController: NSWindowController {

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("guide.title", comment: "")
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 450, height: 400)
        self.init(window: window)
        setupUI()
    }

    // MARK: - UI

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)

        // Conteneur pour le scroll
        let clipView = scrollView.contentView
        scrollView.documentView = stack

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: clipView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: clipView.widthAnchor),
        ])

        buildContent(in: stack)
    }

    private func buildContent(in stack: NSStackView) {
        // ── À propos ──
        addSectionTitle(NSLocalizedString("guide.about.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.about.intro", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.about.features_intro", comment: ""), to: stack)
        addBulletList([
            NSLocalizedString("guide.about.feature.monitoring", comment: ""),
            NSLocalizedString("guide.about.feature.details", comment: ""),
            NSLocalizedString("guide.about.feature.quality", comment: ""),
            NSLocalizedString("guide.about.feature.speed", comment: ""),
            NSLocalizedString("guide.about.feature.traceroute", comment: ""),
            NSLocalizedString("guide.about.feature.dns", comment: ""),
            NSLocalizedString("guide.about.feature.wifi", comment: ""),
            NSLocalizedString("guide.about.feature.neighborhood", comment: ""),
            NSLocalizedString("guide.about.feature.teletravail", comment: ""),
        ], to: stack)

        addSpacer(to: stack)

        // ── Concepts réseau ──
        addSectionTitle(NSLocalizedString("guide.concepts.title", comment: ""), to: stack)

        addSubTitle(NSLocalizedString("guide.concepts.latency.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.concepts.latency.text", comment: ""), to: stack)

        addSubTitle(NSLocalizedString("guide.concepts.jitter.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.concepts.jitter.text", comment: ""), to: stack)

        addSubTitle(NSLocalizedString("guide.concepts.loss.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.concepts.loss.text", comment: ""), to: stack)

        addSubTitle(NSLocalizedString("guide.concepts.speed.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.concepts.speed.text", comment: ""), to: stack)

        addSubTitle(NSLocalizedString("guide.concepts.dns.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.concepts.dns.text", comment: ""), to: stack)

        addSubTitle(NSLocalizedString("guide.concepts.traceroute.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.concepts.traceroute.text", comment: ""), to: stack)

        addSubTitle(NSLocalizedString("guide.concepts.rssi.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.concepts.rssi.text", comment: ""), to: stack)

        addSubTitle(NSLocalizedString("guide.concepts.nat.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.concepts.nat.text", comment: ""), to: stack)

        addSubTitle(NSLocalizedString("guide.concepts.ipv.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.concepts.ipv.text", comment: ""), to: stack)

        addSpacer(to: stack)

        // ── Astuces ──
        addSectionTitle(NSLocalizedString("guide.tips.title", comment: ""), to: stack)

        addSubTitle(NSLocalizedString("guide.tips.router.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.tips.router.text", comment: ""), to: stack)

        addSubTitle(NSLocalizedString("guide.tips.ethernet.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.tips.ethernet.text", comment: ""), to: stack)

        addSubTitle(NSLocalizedString("guide.tips.channel.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.tips.channel.text", comment: ""), to: stack)

        addSubTitle(NSLocalizedString("guide.tips.dns.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.tips.dns.text", comment: ""), to: stack)
        addBulletList([
            NSLocalizedString("guide.tips.dns.cloudflare", comment: ""),
            NSLocalizedString("guide.tips.dns.google", comment: ""),
            NSLocalizedString("guide.tips.dns.quad9", comment: ""),
        ], to: stack)
        addParagraph(NSLocalizedString("guide.tips.dns.outro", comment: ""), to: stack)

        addSubTitle(NSLocalizedString("guide.tips.reboot.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.tips.reboot.text", comment: ""), to: stack)

        addSubTitle(NSLocalizedString("guide.tips.bandwidth.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.tips.bandwidth.text", comment: ""), to: stack)

        addSubTitle(NSLocalizedString("guide.tips.install.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.tips.install.text", comment: ""), to: stack)

        addSpacer(to: stack)

        // ── Télétravail ──
        addSectionTitle(NSLocalizedString("guide.teletravail.title", comment: ""), to: stack)
        addParagraph(NSLocalizedString("guide.teletravail.intro", comment: ""), to: stack)

        // Tableau des seuils par usage
        let usageGrid = NSGridView(numberOfColumns: 6, rows: 0)
        usageGrid.translatesAutoresizingMaskIntoConstraints = false
        usageGrid.columnSpacing = 10
        usageGrid.rowSpacing = 4

        // En-tetes
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
            l.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            l.textColor = .secondaryLabelColor
            return l
        }
        usageGrid.addRow(with: headerViews)

        // Donnees
        let usageData: [(String, String, String, String, String, String)] = [
            (NSLocalizedString("guide.teletravail.usage.visio", comment: ""), "5", "3", "100", "30", "2"),
            (NSLocalizedString("guide.teletravail.usage.visiohd", comment: ""), "15", "8", "50", "20", "1"),
            (NSLocalizedString("guide.teletravail.usage.email", comment: ""), "1", "0.5", "300", "100", "5"),
            (NSLocalizedString("guide.teletravail.usage.citrix", comment: ""), "5", "2", "80", "20", "1"),
            (NSLocalizedString("guide.teletravail.usage.transfer", comment: ""), "10", "5", "500", "100", "3"),
            (NSLocalizedString("guide.teletravail.usage.streaming", comment: ""), "25", "1", "200", "50", "2"),
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

        stack.addArrangedSubview(usageGrid)
        usageGrid.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56).isActive = true

        addParagraph(NSLocalizedString("guide.teletravail.verdicts", comment: ""), to: stack)
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

        addSpacer(to: stack)

        // ── Raccourcis ──
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
            ("E", NSLocalizedString("menu.teletravail", comment: "").replacingOccurrences(of: "…", with: "")),
            ("H", NSLocalizedString("menu.guide", comment: "").replacingOccurrences(of: "…", with: "")),
            (",", NSLocalizedString("menu.settings", comment: "").replacingOccurrences(of: "…", with: "")),
            ("I", NSLocalizedString("menu.about", comment: "").replacingOccurrences(of: "…", with: "")),
            ("Q", NSLocalizedString("menu.quit", comment: "")),
        ]

        let shortcutGrid = NSGridView(numberOfColumns: 2, rows: 0)
        shortcutGrid.translatesAutoresizingMaskIntoConstraints = false
        shortcutGrid.columnSpacing = 16
        shortcutGrid.rowSpacing = 4
        shortcutGrid.column(at: 0).xPlacement = .trailing
        shortcutGrid.column(at: 0).width = 50
        shortcutGrid.column(at: 1).xPlacement = .leading

        for (key, desc) in shortcuts {
            let keyLabel = NSTextField(labelWithString: "⌘\(key)")
            keyLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
            keyLabel.textColor = .secondaryLabelColor
            let descLabel = NSTextField(labelWithString: desc)
            descLabel.font = NSFont.systemFont(ofSize: 13)
            shortcutGrid.addRow(with: [keyLabel, descLabel])
        }

        stack.addArrangedSubview(shortcutGrid)
        shortcutGrid.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56).isActive = true
    }

    // MARK: - Helpers

    private func addSectionTitle(_ text: String, to stack: NSStackView) {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        stack.addArrangedSubview(spacer)

        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(label)
    }

    private func addSubTitle(_ text: String, to stack: NSStackView) {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 4).isActive = true
        stack.addArrangedSubview(spacer)

        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .controlAccentColor
        label.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(label)
    }

    private func addParagraph(_ text: String, to stack: NSStackView) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isSelectable = true
        stack.addArrangedSubview(label)
    }

    private func addBulletList(_ items: [String], to stack: NSStackView) {
        let text = items.map { "  •  \($0)" }.joined(separator: "\n")
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isSelectable = true
        stack.addArrangedSubview(label)
    }

    private func addSpacer(to stack: NSStackView) {
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56).isActive = true
    }
}

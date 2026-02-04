// WiFiWindowController.swift
// Fenetre d'informations WiFi en temps reel avec graphe RSSI.
// Utilise CoreWLAN pour recuperer les infos de l'interface WiFi.

import Cocoa
import CoreWLAN

// MARK: - RSSI Graph View

/// Vue personnalisee qui dessine le graphe RSSI en temps reel.
class RSSIGraphView: NSView {

    var rssiValues: [Int] = [] {
        didSet {
            needsDisplay = true
            if let last = rssiValues.last {
                setAccessibilityValue("Signal \(last) dBm")
            }
        }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.image)
        setAccessibilityLabel(NSLocalizedString("wifi.accessibility.graph", comment: ""))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityRole(.image)
        setAccessibilityLabel(NSLocalizedString("wifi.accessibility.graph", comment: ""))
    }

    // MARK: - Tooltip interactif

    private var tooltipView: NSTextField?
    private var cursorLineX: CGFloat?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let margin = CGFloat(45)
        let graphRect = NSRect(x: margin, y: 10, width: bounds.width - margin - 10, height: bounds.height - 30)
        guard graphRect.contains(point), rssiValues.count > 1 else { hideTooltip(); return }

        let spacing = graphRect.width / CGFloat(max(rssiValues.count - 1, 1))
        let index = Int(round((point.x - graphRect.minX) / spacing))
        guard index >= 0, index < rssiValues.count else { hideTooltip(); return }

        cursorLineX = graphRect.minX + CGFloat(index) * spacing
        needsDisplay = true

        let rssi = rssiValues[index]
        let text: String
        if rssi == WiFiWindowController.noSignalValue {
            text = String(format: NSLocalizedString("wifi.tooltip.disconnected", comment: ""), index + 1, rssiValues.count)
        } else {
            text = String(format: NSLocalizedString("wifi.tooltip.rssi", comment: ""), index + 1, rssiValues.count, rssi)
        }

        if tooltipView == nil {
            let label = NSTextField(labelWithString: "")
            label.font = NSFont.systemFont(ofSize: 10)
            label.backgroundColor = NSColor.windowBackgroundColor
            label.drawsBackground = true
            label.isBezeled = true
            label.bezelStyle = .roundedBezel
            label.maximumNumberOfLines = 2
            addSubview(label)
            tooltipView = label
        }
        tooltipView?.stringValue = text
        tooltipView?.sizeToFit()
        var origin = NSPoint(x: cursorLineX! + 8, y: point.y - 16)
        if let tv = tooltipView, origin.x + tv.frame.width > bounds.maxX - 10 {
            origin.x = cursorLineX! - tv.frame.width - 8
        }
        tooltipView?.frame.origin = origin
        tooltipView?.isHidden = false
    }

    override func mouseExited(with event: NSEvent) { hideTooltip() }

    private func hideTooltip() {
        tooltipView?.isHidden = true
        cursorLineX = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds

        // Fond
        context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        context.fill(rect)

        let margin = CGFloat(45)
        let graphRect = NSRect(
            x: margin, y: 10,
            width: rect.width - margin - 10,
            height: rect.height - 30
        )

        // Cadre
        context.setStrokeColor(NSColor.separatorColor.cgColor)
        context.setLineWidth(1)
        context.stroke(graphRect)

        let hasRealValues = rssiValues.contains(where: { $0 != WiFiWindowController.noSignalValue })
        guard rssiValues.count > 1 && hasRealValues else {
            drawCenteredText(NSLocalizedString("wifi.graph.waiting", comment: ""), in: graphRect, context: context)
            return
        }

        // Echelle RSSI : -100 dBm (bas) a -20 dBm (haut)
        let minRSSI: Double = -100
        let maxRSSI: Double = -20
        let range = maxRSSI - minRSSI

        // Grille
        drawGrid(in: graphRect, minRSSI: minRSSI, maxRSSI: maxRSSI, context: context)

        let noSig = WiFiWindowController.noSignalValue
        let pointSpacing = graphRect.width / CGFloat(max(rssiValues.count - 1, 1))

        // --- Zones grisees pour les points deconnectes ---
        var disconnectStart: Int? = nil
        for i in 0...rssiValues.count {
            let isDisconnected = i < rssiValues.count && rssiValues[i] == noSig
            if isDisconnected && disconnectStart == nil {
                disconnectStart = i
            } else if !isDisconnected, let start = disconnectStart {
                let x0 = graphRect.minX + CGFloat(start) * pointSpacing - pointSpacing / 2
                let x1 = graphRect.minX + CGFloat(i - 1) * pointSpacing + pointSpacing / 2
                let zoneRect = CGRect(
                    x: max(x0, graphRect.minX),
                    y: graphRect.minY,
                    width: min(x1, graphRect.maxX) - max(x0, graphRect.minX),
                    height: graphRect.height
                )
                context.setFillColor(NSColor.systemGray.withAlphaComponent(0.12).cgColor)
                context.fill(zoneRect)

                // Hachures diagonales
                context.saveGState()
                context.clip(to: zoneRect)
                context.setStrokeColor(NSColor.systemGray.withAlphaComponent(0.18).cgColor)
                context.setLineWidth(0.5)
                let step: CGFloat = 8
                var lx = zoneRect.minX - zoneRect.height
                while lx < zoneRect.maxX {
                    context.move(to: CGPoint(x: lx, y: zoneRect.maxY))
                    context.addLine(to: CGPoint(x: lx + zoneRect.height, y: zoneRect.minY))
                    lx += step
                }
                context.strokePath()
                context.restoreGState()

                disconnectStart = nil
            }
        }

        // --- Aire remplie sous la courbe (segments connectes uniquement) ---
        var areaPath = CGMutablePath()
        var started = false

        for (i, rssi) in rssiValues.enumerated() {
            let x = graphRect.minX + CGFloat(i) * pointSpacing
            if rssi == noSig {
                if started {
                    areaPath.addLine(to: CGPoint(x: graphRect.minX + CGFloat(i - 1) * pointSpacing, y: graphRect.maxY))
                    areaPath.closeSubpath()
                    started = false
                }
                continue
            }
            let normalized = (Double(rssi) - minRSSI) / range
            let y = graphRect.maxY - CGFloat(normalized) * (graphRect.height - 20)
            if !started {
                areaPath.move(to: CGPoint(x: x, y: graphRect.maxY))
                areaPath.addLine(to: CGPoint(x: x, y: y))
                started = true
            } else {
                areaPath.addLine(to: CGPoint(x: x, y: y))
            }
        }
        if started {
            let lastValid = rssiValues.lastIndex(where: { $0 != noSig }) ?? 0
            areaPath.addLine(to: CGPoint(x: graphRect.minX + CGFloat(lastValid) * pointSpacing, y: graphRect.maxY))
            areaPath.closeSubpath()
        }

        context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.1).cgColor)
        context.addPath(areaPath)
        context.fillPath()

        // --- Courbe RSSI (interrompue sur les deconnexions) ---
        let linePath = CGMutablePath()
        started = false

        for (i, rssi) in rssiValues.enumerated() {
            if rssi == noSig {
                started = false
                continue
            }
            let x = graphRect.minX + CGFloat(i) * pointSpacing
            let normalized = (Double(rssi) - minRSSI) / range
            let y = graphRect.maxY - CGFloat(normalized) * (graphRect.height - 20)
            if !started {
                linePath.move(to: CGPoint(x: x, y: y))
                started = true
            } else {
                linePath.addLine(to: CGPoint(x: x, y: y))
            }
        }

        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(2)
        context.addPath(linePath)
        context.strokePath()

        // --- Points avec couleur selon le niveau (connectes uniquement) ---
        for (i, rssi) in rssiValues.enumerated() {
            if rssi == noSig { continue }
            let x = graphRect.minX + CGFloat(i) * pointSpacing
            let normalized = (Double(rssi) - minRSSI) / range
            let y = graphRect.maxY - CGFloat(normalized) * (graphRect.height - 20)
            let dotRect = CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)

            let color: NSColor
            if rssi >= -50 {
                color = .systemGreen
            } else if rssi >= -70 {
                color = .systemOrange
            } else {
                color = .systemRed
            }
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: dotRect)
        }

        // Zones de qualite (fond colore)
        drawQualityZones(in: graphRect, minRSSI: minRSSI, maxRSSI: maxRSSI, context: context)

        // Cursor line
        if let cx = cursorLineX {
            context.setStrokeColor(NSColor.labelColor.withAlphaComponent(0.4).cgColor)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [4, 3])
            context.move(to: CGPoint(x: cx, y: graphRect.minY))
            context.addLine(to: CGPoint(x: cx, y: graphRect.maxY))
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
        }
    }

    private func drawGrid(in graphRect: NSRect, minRSSI: Double, maxRSSI: Double, context: CGContext) {
        let range = maxRSSI - minRSSI
        context.setStrokeColor(NSColor.separatorColor.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(0.5)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]

        for dbm in stride(from: -90, through: -30, by: 10) {
            let normalized = (Double(dbm) - minRSSI) / range
            let y = graphRect.maxY - CGFloat(normalized) * (graphRect.height - 20)
            if y > graphRect.minY + 10 && y < graphRect.maxY - 5 {
                context.move(to: CGPoint(x: graphRect.minX, y: y))
                context.addLine(to: CGPoint(x: graphRect.maxX, y: y))
                context.strokePath()

                let label = NSAttributedString(string: "\(dbm)", attributes: attrs)
                label.draw(at: NSPoint(x: graphRect.minX - 40, y: y - 6))
            }
        }

        let unitLabel = NSAttributedString(string: "dBm", attributes: attrs)
        unitLabel.draw(at: NSPoint(x: graphRect.minX - 35, y: graphRect.minY - 2))
    }

    private func drawQualityZones(in graphRect: NSRect, minRSSI: Double, maxRSSI: Double, context: CGContext) {
        let range = maxRSSI - minRSSI
        let h = graphRect.height - 20

        // Excellent : -20 a -50
        let excellentTop = graphRect.maxY - CGFloat((-20 - minRSSI) / range) * h
        let excellentBot = graphRect.maxY - CGFloat((-50 - minRSSI) / range) * h
        context.setFillColor(NSColor.systemGreen.withAlphaComponent(0.04).cgColor)
        context.fill(CGRect(x: graphRect.minX, y: excellentTop, width: graphRect.width, height: excellentBot - excellentTop))

        // Moyen : -50 a -70
        let medBot = graphRect.maxY - CGFloat((-70 - minRSSI) / range) * h
        context.setFillColor(NSColor.systemOrange.withAlphaComponent(0.04).cgColor)
        context.fill(CGRect(x: graphRect.minX, y: excellentBot, width: graphRect.width, height: medBot - excellentBot))

        // Mauvais : -70 a -100
        context.setFillColor(NSColor.systemRed.withAlphaComponent(0.04).cgColor)
        context.fill(CGRect(x: graphRect.minX, y: medBot, width: graphRect.width, height: graphRect.maxY - medBot))
    }

    private func drawCenteredText(_ text: String, in rect: NSRect, context: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        str.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }
}

// MARK: - RSSI Gauge View

/// Barre horizontale coloree selon la force du signal (memes couleurs que le graphe).
class RSSIGaugeView: NSView {

    /// Valeur entre 0 et 100.
    var value: Double = 0 { didSet { needsDisplay = true; updateAccessibilityValue() } }

    /// RSSI brut pour determiner la couleur.
    var rssi: Int = -100 { didSet { needsDisplay = true; updateAccessibilityValue() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.levelIndicator)
        setAccessibilityLabel(NSLocalizedString("wifi.accessibility.gauge", comment: ""))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityRole(.levelIndicator)
        setAccessibilityLabel(NSLocalizedString("wifi.accessibility.gauge", comment: ""))
    }

    private func updateAccessibilityValue() {
        setAccessibilityValue("\(rssi) dBm, \(Int(value))%")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let rect = bounds

        // Fond
        context.setFillColor(NSColor.separatorColor.withAlphaComponent(0.2).cgColor)
        let bgPath = CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
        context.addPath(bgPath)
        context.fillPath()

        // Barre remplie
        let fillWidth = max(0, min(rect.width, rect.width * CGFloat(value / 100.0)))
        guard fillWidth > 0 else { return }

        let fillRect = CGRect(x: rect.origin.x, y: rect.origin.y, width: fillWidth, height: rect.height)
        let color: NSColor
        if rssi >= -50 {
            color = .systemGreen
        } else if rssi >= -70 {
            color = .systemOrange
        } else {
            color = .systemRed
        }
        context.setFillColor(color.cgColor)
        let fillPath = CGPath(roundedRect: fillRect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
        context.addPath(fillPath)
        context.fillPath()
    }
}

// MARK: - WiFi Window Controller

class WiFiWindowController: NSWindowController {

    // Labels d'info (colonne gauche)
    private var ssidLabel: NSTextField!
    private var bssidLabel: NSTextField!
    private var securityLabel: NSTextField!
    private var rssiLabel: NSTextField!
    private var snrLabel: NSTextField!
    private var modeLabel: NSTextField!

    // Labels d'info (colonne droite)
    private var channelLabel: NSTextField!
    private var bandLabel: NSTextField!
    private var widthLabel: NSTextField!
    private var noiseLabel: NSTextField!
    private var txRateLabel: NSTextField!
    private var countryLabel: NSTextField!

    // Jauge RSSI
    private var rssiGaugeView: RSSIGaugeView!
    private var rssiGaugeLabel: NSTextField!

    // Graphe
    private var graphView: RSSIGraphView!

    // Etat
    private var refreshTimer: Timer?
    private var rssiHistory: [Int] = []
    private let maxPoints = 120

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("wifi.window.title", comment: "")
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 450, height: 400)

        self.init(window: window)
        setupUI()
        refresh()
        startAutoRefresh()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        // Titre
        let titleLabel = NSTextField(labelWithString: NSLocalizedString("wifi.heading", comment: ""))
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        // Grille d'infos
        let infoGrid = createInfoGrid()
        infoGrid.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(infoGrid)

        // Jauge RSSI
        let gaugeContainer = NSView()
        gaugeContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(gaugeContainer)

        let gaugeTitle = NSTextField(labelWithString: NSLocalizedString("wifi.gauge.label", comment: ""))
        gaugeTitle.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        gaugeTitle.translatesAutoresizingMaskIntoConstraints = false
        gaugeContainer.addSubview(gaugeTitle)

        rssiGaugeView = RSSIGaugeView()
        rssiGaugeView.translatesAutoresizingMaskIntoConstraints = false
        gaugeContainer.addSubview(rssiGaugeView)

        rssiGaugeLabel = NSTextField(labelWithString: NSLocalizedString("wifi.gauge.no_signal", comment: ""))
        rssiGaugeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        rssiGaugeLabel.translatesAutoresizingMaskIntoConstraints = false
        gaugeContainer.addSubview(rssiGaugeLabel)

        NSLayoutConstraint.activate([
            gaugeTitle.leadingAnchor.constraint(equalTo: gaugeContainer.leadingAnchor),
            gaugeTitle.centerYAnchor.constraint(equalTo: gaugeContainer.centerYAnchor),
            rssiGaugeView.leadingAnchor.constraint(equalTo: gaugeTitle.trailingAnchor, constant: 8),
            rssiGaugeView.centerYAnchor.constraint(equalTo: gaugeContainer.centerYAnchor),
            rssiGaugeView.heightAnchor.constraint(equalToConstant: 12),
            rssiGaugeView.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            rssiGaugeLabel.leadingAnchor.constraint(equalTo: rssiGaugeView.trailingAnchor, constant: 8),
            rssiGaugeLabel.trailingAnchor.constraint(equalTo: gaugeContainer.trailingAnchor),
            rssiGaugeLabel.centerYAnchor.constraint(equalTo: gaugeContainer.centerYAnchor),
            gaugeContainer.heightAnchor.constraint(equalToConstant: 20),
        ])

        // Legende graphe
        let legendStack = NSStackView()
        legendStack.orientation = .horizontal
        legendStack.spacing = 16
        legendStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(legendStack)

        func legendDot(color: NSColor, label: String) -> NSView {
            let c = NSStackView()
            c.orientation = .horizontal
            c.spacing = 4
            let box = NSView()
            box.wantsLayer = true
            box.layer?.backgroundColor = color.cgColor
            box.layer?.cornerRadius = 4
            box.translatesAutoresizingMaskIntoConstraints = false
            box.widthAnchor.constraint(equalToConstant: 10).isActive = true
            box.heightAnchor.constraint(equalToConstant: 10).isActive = true
            let t = NSTextField(labelWithString: label)
            t.font = NSFont.systemFont(ofSize: 11)
            t.textColor = .secondaryLabelColor
            c.addArrangedSubview(box)
            c.addArrangedSubview(t)
            return c
        }

        legendStack.addArrangedSubview(legendDot(color: .systemGreen, label: NSLocalizedString("wifi.legend.excellent", comment: "")))
        legendStack.addArrangedSubview(legendDot(color: .systemOrange, label: NSLocalizedString("wifi.legend.medium", comment: "")))
        legendStack.addArrangedSubview(legendDot(color: .systemRed, label: NSLocalizedString("wifi.legend.weak", comment: "")))

        // Graphe RSSI
        graphView = RSSIGraphView()
        graphView.translatesAutoresizingMaskIntoConstraints = false
        graphView.wantsLayer = true
        graphView.layer?.cornerRadius = 4
        contentView.addSubview(graphView)

        // Contraintes
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            infoGrid.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            infoGrid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            infoGrid.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            gaugeContainer.topAnchor.constraint(equalTo: infoGrid.bottomAnchor, constant: 12),
            gaugeContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            gaugeContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            legendStack.topAnchor.constraint(equalTo: gaugeContainer.bottomAnchor, constant: 12),
            legendStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            graphView.topAnchor.constraint(equalTo: legendStack.bottomAnchor, constant: 8),
            graphView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            graphView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            graphView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    private func createInfoGrid() -> NSView {
        let grid = NSGridView(numberOfColumns: 4, rows: 0)
        grid.rowSpacing = 6
        grid.columnSpacing = 8

        // Style des labels
        func titleCell(_ text: String) -> NSTextField {
            let l = NSTextField(labelWithString: text)
            l.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            l.textColor = .secondaryLabelColor
            l.alignment = .right
            return l
        }

        func valueCell() -> NSTextField {
            let l = NSTextField(labelWithString: "—")
            l.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            return l
        }

        // Creer les labels de valeur
        ssidLabel = valueCell()
        bssidLabel = valueCell()
        securityLabel = valueCell()
        rssiLabel = valueCell()
        snrLabel = valueCell()
        modeLabel = valueCell()

        channelLabel = valueCell()
        bandLabel = valueCell()
        widthLabel = valueCell()
        noiseLabel = valueCell()
        txRateLabel = valueCell()
        countryLabel = valueCell()

        // Remplir la grille (2 colonnes de paires titre/valeur)
        grid.addRow(with: [titleCell(NSLocalizedString("wifi.label.ssid", comment: "")), ssidLabel, titleCell(NSLocalizedString("wifi.label.channel", comment: "")), channelLabel])
        grid.addRow(with: [titleCell(NSLocalizedString("wifi.label.bssid", comment: "")), bssidLabel, titleCell(NSLocalizedString("wifi.label.band", comment: "")), bandLabel])
        grid.addRow(with: [titleCell(NSLocalizedString("wifi.label.security", comment: "")), securityLabel, titleCell(NSLocalizedString("wifi.label.width", comment: "")), widthLabel])
        grid.addRow(with: [titleCell(NSLocalizedString("wifi.label.rssi", comment: "")), rssiLabel, titleCell(NSLocalizedString("wifi.label.noise", comment: "")), noiseLabel])
        grid.addRow(with: [titleCell(NSLocalizedString("wifi.label.snr", comment: "")), snrLabel, titleCell(NSLocalizedString("wifi.label.txrate", comment: "")), txRateLabel])
        grid.addRow(with: [titleCell(NSLocalizedString("wifi.label.mode", comment: "")), modeLabel, titleCell(NSLocalizedString("wifi.label.country", comment: "")), countryLabel])

        // Largeur des colonnes titre
        grid.column(at: 0).width = 70
        grid.column(at: 2).width = 70

        return grid
    }

    /// Valeur sentinelle indiquant "pas de signal" dans l'historique.
    static let noSignalValue = Int.min

    private func appendDisconnectedPoint() {
        rssiHistory.append(WiFiWindowController.noSignalValue)
        if rssiHistory.count > maxPoints {
            rssiHistory.removeFirst(rssiHistory.count - maxPoints)
        }
        graphView.rssiValues = rssiHistory
    }

    // MARK: - Rafraichissement

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        guard let client = CWWiFiClient.shared().interface() else {
            ssidLabel.stringValue = NSLocalizedString("wifi.status.disconnected", comment: "")
            bssidLabel.stringValue = "—"
            securityLabel.stringValue = "—"
            rssiLabel.stringValue = "—"
            noiseLabel.stringValue = "—"
            snrLabel.stringValue = "—"
            channelLabel.stringValue = "—"
            bandLabel.stringValue = "—"
            widthLabel.stringValue = "—"
            txRateLabel.stringValue = "—"
            modeLabel.stringValue = "—"
            countryLabel.stringValue = "—"
            rssiGaugeView.value = 0
            rssiGaugeView.rssi = -100
            rssiGaugeLabel.stringValue = NSLocalizedString("wifi.gauge.no_signal", comment: "")
            appendDisconnectedPoint()
            window?.title = NSLocalizedString("wifi.window.title.disconnected", comment: "")
            return
        }

        // Verifier que le WiFi est associe a un reseau
        // Note: ssid() peut retourner nil sur macOS Sonoma+ si les permissions de localisation ne sont pas accordees
        // On utilise wlanChannel() pour detecter si le WiFi est connecte meme sans acces au SSID
        let ssid = client.ssid()
        let channel = client.wlanChannel()
        let rssi = client.rssiValue()

        // Si pas de canal et RSSI invalide, le WiFi n'est vraiment pas connecte
        let isConnected = channel != nil || (rssi != 0 && rssi > -100)

        guard isConnected else {
            ssidLabel.stringValue = NSLocalizedString("wifi.status.disconnected", comment: "")
            bssidLabel.stringValue = "—"
            securityLabel.stringValue = "—"
            rssiLabel.stringValue = "—"
            noiseLabel.stringValue = "—"
            snrLabel.stringValue = "—"
            channelLabel.stringValue = "—"
            bandLabel.stringValue = "—"
            widthLabel.stringValue = "—"
            txRateLabel.stringValue = "—"
            modeLabel.stringValue = "—"
            countryLabel.stringValue = "—"
            rssiGaugeView.value = 0
            rssiGaugeView.rssi = -100
            rssiGaugeLabel.stringValue = NSLocalizedString("wifi.gauge.no_signal", comment: "")
            appendDisconnectedPoint()
            window?.title = NSLocalizedString("wifi.window.title.disconnected", comment: "")
            return
        }

        // Afficher le SSID ou "SSID privé" si non accessible (permissions de localisation)
        let displaySSID = (ssid != nil && !ssid!.isEmpty) ? ssid! : NSLocalizedString("wifi.status.private_ssid", comment: "")
        ssidLabel.stringValue = displaySSID
        window?.title = String(format: NSLocalizedString("wifi.window.title.connected", comment: ""), displaySSID)

        // BSSID
        bssidLabel.stringValue = client.bssid() ?? "—"

        // Securite
        let security = client.security()
        let secStr: String
        switch security {
        case .none: secStr = NSLocalizedString("wifi.security.none", comment: "")
        case .WEP: secStr = "WEP"
        case .wpaPersonal: secStr = NSLocalizedString("wifi.security.wpa_personal", comment: "")
        case .wpaEnterprise: secStr = NSLocalizedString("wifi.security.wpa_enterprise", comment: "")
        case .wpa2Personal: secStr = NSLocalizedString("wifi.security.wpa2_personal", comment: "")
        case .wpa2Enterprise: secStr = NSLocalizedString("wifi.security.wpa2_enterprise", comment: "")
        case .wpa3Personal: secStr = NSLocalizedString("wifi.security.wpa3_personal", comment: "")
        case .wpa3Enterprise: secStr = NSLocalizedString("wifi.security.wpa3_enterprise", comment: "")
        default: secStr = NSLocalizedString("wifi.security.other", comment: "")
        }
        securityLabel.stringValue = secStr

        // RSSI et bruit (rssi deja recupere plus haut pour detecter la connexion)
        let noise = client.noiseMeasurement()
        let snr = rssi - noise

        rssiLabel.stringValue = "\(rssi) dBm"
        rssiLabel.textColor = rssi >= -50 ? .systemGreen : (rssi >= -70 ? .systemOrange : .systemRed)
        noiseLabel.stringValue = "\(noise) dBm"
        snrLabel.stringValue = "\(snr) dB"

        // Jauge RSSI : mapper -100..-20 vers 0..100
        let gaugeValue = max(0, min(100, Double(rssi + 100) * (100.0 / 80.0)))
        rssiGaugeView.value = gaugeValue
        rssiGaugeView.rssi = rssi
        rssiGaugeLabel.stringValue = "\(rssi) dBm"

        // Canal
        if let channel = client.wlanChannel() {
            channelLabel.stringValue = "\(channel.channelNumber)"

            switch channel.channelBand {
            case .band2GHz: bandLabel.stringValue = "2.4 GHz"
            case .band5GHz: bandLabel.stringValue = "5 GHz"
            case .band6GHz: bandLabel.stringValue = "6 GHz"
            default: bandLabel.stringValue = NSLocalizedString("wifi.unknown", comment: "")
            }

            switch channel.channelWidth {
            case .width20MHz: widthLabel.stringValue = "20 MHz"
            case .width40MHz: widthLabel.stringValue = "40 MHz"
            case .width80MHz: widthLabel.stringValue = "80 MHz"
            case .width160MHz: widthLabel.stringValue = "160 MHz"
            default: widthLabel.stringValue = NSLocalizedString("wifi.unknown", comment: "")
            }
        } else {
            channelLabel.stringValue = "—"
            bandLabel.stringValue = "—"
            widthLabel.stringValue = "—"
        }

        // Debit TX
        let txRate = client.transmitRate()
        txRateLabel.stringValue = txRate > 0 ? String(format: "%.0f Mbps", txRate) : "—"

        // Mode PHY
        modeLabel.stringValue = client.activePHYMode().description

        // Code pays
        countryLabel.stringValue = client.countryCode() ?? "—"

        // Historique RSSI pour le graphe (ignorer les valeurs incoherentes)
        if rssi < 0 && rssi >= -100 {
            rssiHistory.append(rssi)
            if rssiHistory.count > maxPoints {
                rssiHistory.removeFirst(rssiHistory.count - maxPoints)
            }
            graphView.rssiValues = rssiHistory
        }
    }

    override func close() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        super.close()
    }

    deinit {
        refreshTimer?.invalidate()
    }
}

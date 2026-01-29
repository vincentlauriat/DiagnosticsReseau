// WiFiWindowController.swift
// Fenetre d'informations WiFi en temps reel avec graphe RSSI.
// Utilise CoreWLAN pour recuperer les infos de l'interface WiFi.

import Cocoa
import CoreWLAN

// MARK: - RSSI Graph View

/// Vue personnalisee qui dessine le graphe RSSI en temps reel.
class RSSIGraphView: NSView {

    var rssiValues: [Int] = [] {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

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

        guard rssiValues.count > 1 else {
            drawCenteredText("En attente de donnees...", in: graphRect, context: context)
            return
        }

        // Echelle RSSI : -100 dBm (bas) a -20 dBm (haut)
        let minRSSI: Double = -100
        let maxRSSI: Double = -20
        let range = maxRSSI - minRSSI

        // Grille
        drawGrid(in: graphRect, minRSSI: minRSSI, maxRSSI: maxRSSI, context: context)

        let pointSpacing = graphRect.width / CGFloat(max(rssiValues.count - 1, 1))

        // Aire remplie sous la courbe
        let areaPath = CGMutablePath()
        var started = false

        for (i, rssi) in rssiValues.enumerated() {
            let x = graphRect.minX + CGFloat(i) * pointSpacing
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
        // Fermer vers le bas
        let lastX = graphRect.minX + CGFloat(rssiValues.count - 1) * pointSpacing
        areaPath.addLine(to: CGPoint(x: lastX, y: graphRect.maxY))
        areaPath.closeSubpath()

        context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.1).cgColor)
        context.addPath(areaPath)
        context.fillPath()

        // Courbe RSSI
        let linePath = CGMutablePath()
        started = false

        for (i, rssi) in rssiValues.enumerated() {
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

        // Points avec couleur selon le niveau
        for (i, rssi) in rssiValues.enumerated() {
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
    private var rssiGauge: NSProgressIndicator!
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
        window.title = "Mon Réseau — WiFi"
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
        let titleLabel = NSTextField(labelWithString: "Informations WiFi")
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

        let gaugeTitle = NSTextField(labelWithString: "Signal :")
        gaugeTitle.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        gaugeTitle.translatesAutoresizingMaskIntoConstraints = false
        gaugeContainer.addSubview(gaugeTitle)

        rssiGauge = NSProgressIndicator()
        rssiGauge.style = .bar
        rssiGauge.isIndeterminate = false
        rssiGauge.minValue = 0
        rssiGauge.maxValue = 100
        rssiGauge.doubleValue = 0
        rssiGauge.translatesAutoresizingMaskIntoConstraints = false
        gaugeContainer.addSubview(rssiGauge)

        rssiGaugeLabel = NSTextField(labelWithString: "— dBm")
        rssiGaugeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        rssiGaugeLabel.translatesAutoresizingMaskIntoConstraints = false
        gaugeContainer.addSubview(rssiGaugeLabel)

        NSLayoutConstraint.activate([
            gaugeTitle.leadingAnchor.constraint(equalTo: gaugeContainer.leadingAnchor),
            gaugeTitle.centerYAnchor.constraint(equalTo: gaugeContainer.centerYAnchor),
            rssiGauge.leadingAnchor.constraint(equalTo: gaugeTitle.trailingAnchor, constant: 8),
            rssiGauge.centerYAnchor.constraint(equalTo: gaugeContainer.centerYAnchor),
            rssiGauge.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            rssiGaugeLabel.leadingAnchor.constraint(equalTo: rssiGauge.trailingAnchor, constant: 8),
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

        legendStack.addArrangedSubview(legendDot(color: .systemGreen, label: "Excellent (> -50)"))
        legendStack.addArrangedSubview(legendDot(color: .systemOrange, label: "Moyen (-50 a -70)"))
        legendStack.addArrangedSubview(legendDot(color: .systemRed, label: "Faible (< -70)"))

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
        grid.addRow(with: [titleCell("SSID :"), ssidLabel, titleCell("Canal :"), channelLabel])
        grid.addRow(with: [titleCell("BSSID :"), bssidLabel, titleCell("Bande :"), bandLabel])
        grid.addRow(with: [titleCell("Securite :"), securityLabel, titleCell("Largeur :"), widthLabel])
        grid.addRow(with: [titleCell("RSSI :"), rssiLabel, titleCell("Bruit :"), noiseLabel])
        grid.addRow(with: [titleCell("SNR :"), snrLabel, titleCell("Debit TX :"), txRateLabel])
        grid.addRow(with: [titleCell("Mode :"), modeLabel, titleCell("Pays :"), countryLabel])

        // Largeur des colonnes titre
        grid.column(at: 0).width = 70
        grid.column(at: 2).width = 70

        return grid
    }

    // MARK: - Rafraichissement

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        guard let client = CWWiFiClient.shared().interface() else {
            ssidLabel.stringValue = "Non connecte"
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
            rssiGauge.doubleValue = 0
            rssiGaugeLabel.stringValue = "— dBm"
            window?.title = "Mon Réseau — WiFi (deconnecte)"
            return
        }

        // SSID
        let ssid = client.ssid() ?? "Inconnu"
        ssidLabel.stringValue = ssid
        window?.title = "Mon Réseau — WiFi — \(ssid)"

        // BSSID
        bssidLabel.stringValue = client.bssid() ?? "—"

        // Securite
        let security = client.security()
        let secStr: String
        switch security {
        case .none: secStr = "Aucune"
        case .WEP: secStr = "WEP"
        case .wpaPersonal: secStr = "WPA Personnel"
        case .wpaEnterprise: secStr = "WPA Enterprise"
        case .wpa2Personal: secStr = "WPA2 Personnel"
        case .wpa2Enterprise: secStr = "WPA2 Enterprise"
        case .wpa3Personal: secStr = "WPA3 Personnel"
        case .wpa3Enterprise: secStr = "WPA3 Enterprise"
        default: secStr = "Autre"
        }
        securityLabel.stringValue = secStr

        // RSSI et bruit
        let rssi = client.rssiValue()
        let noise = client.noiseMeasurement()
        let snr = rssi - noise

        rssiLabel.stringValue = "\(rssi) dBm"
        rssiLabel.textColor = rssi >= -50 ? .systemGreen : (rssi >= -70 ? .systemOrange : .systemRed)
        noiseLabel.stringValue = "\(noise) dBm"
        snrLabel.stringValue = "\(snr) dB"

        // Jauge RSSI : mapper -100..-20 vers 0..100
        let gaugeValue = max(0, min(100, Double(rssi + 100) * (100.0 / 80.0)))
        rssiGauge.doubleValue = gaugeValue
        rssiGaugeLabel.stringValue = "\(rssi) dBm"

        // Canal
        if let channel = client.wlanChannel() {
            channelLabel.stringValue = "\(channel.channelNumber)"

            switch channel.channelBand {
            case .band2GHz: bandLabel.stringValue = "2.4 GHz"
            case .band5GHz: bandLabel.stringValue = "5 GHz"
            case .band6GHz: bandLabel.stringValue = "6 GHz"
            default: bandLabel.stringValue = "Inconnue"
            }

            switch channel.channelWidth {
            case .width20MHz: widthLabel.stringValue = "20 MHz"
            case .width40MHz: widthLabel.stringValue = "40 MHz"
            case .width80MHz: widthLabel.stringValue = "80 MHz"
            case .width160MHz: widthLabel.stringValue = "160 MHz"
            default: widthLabel.stringValue = "Inconnue"
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

        // Historique RSSI pour le graphe
        rssiHistory.append(rssi)
        if rssiHistory.count > maxPoints {
            rssiHistory.removeFirst(rssiHistory.count - maxPoints)
        }
        graphView.rssiValues = rssiHistory
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

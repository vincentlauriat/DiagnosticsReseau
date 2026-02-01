// NetworkQualityWindowController.swift
// Fenêtre d'analyse de la qualité réseau (latence, jitter, perte de paquets)
// Affiche un graphe en temps réel basé sur des pings périodiques (1/s) vers 8.8.8.8.
// Contient aussi `NetworkGraphView` qui dessine le graphe via Core Graphics.

import Cocoa
import Network
import SystemConfiguration

/// Mesure individuelle d'un ping.
/// - `timestamp`: date de la mesure
/// - `latency`: latence en millisecondes (nil si timeout)
/// - `packetLoss`: vrai si la réponse n'est pas reçue (timeout)
struct PingMeasurement {
    let timestamp: Date
    let latency: Double?     // ms, nil = timeout
    let packetLoss: Bool
}

/// Snapshot de qualité réseau pour l'historique persisté.
struct QualitySnapshot: Codable {
    let date: Date
    let avgLatency: Double
    let jitter: Double
    let lossPercent: Double
    let quality: String
}

/// Stockage de l'historique de qualité réseau dans UserDefaults.
class QualityHistoryStorage {
    private static let key = "QualityHistory"
    private static let maxEntries = 2880 // 24h à raison d'un snapshot toutes les 30s

    static func load() -> [QualitySnapshot] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([QualitySnapshot].self, from: data) else {
            return []
        }
        return entries
    }

    static func add(_ entry: QualitySnapshot) {
        var entries = load()
        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries = Array(entries.prefix(maxEntries)) }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Contrôleur de fenêtre affichant les mesures et le graphe en direct.
class NetworkQualityWindowController: NSWindowController {

    // UI et état
    // - `graphView`: vue de graphe
    // - `statsLabel`: résumé chiffré (moy, min, max, jitter, pertes)
    // - `measurements`: tampon glissant des mesures (max `maxPoints`)
    // - `pingTimer`: timer 1 Hz déclenchant un ping
    private var graphView: NetworkGraphView!
    private var statsLabel: NSTextField!
    private var pingModeControl: NSSegmentedControl!
    private var pingTargetLabel: NSTextField!
    private var measurements: [PingMeasurement] = []
    private let maxPoints = 120 // 2 minutes at 1/s
    private var pingTimer: Timer?
    private var pingMode: PingMode = .internet
    private var snapshotCounter = 0
    private var customHostField: NSTextField!

    enum PingMode: Int {
        case internet = 0
        case local = 1
        case custom = 2
    }

    // Configure la fenetre (taille, titre) puis lance la mesure automatiquement
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("quality.title", comment: "")
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 350)

        self.init(window: window)
        setupUI()
        startMeasuring()
    }

    // Construit l'interface: barre de stats, légende et graphe
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        // Stats bar at top
        statsLabel = NSTextField(labelWithString: NSLocalizedString("quality.status.starting", comment: ""))
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        statsLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        statsLabel.textColor = .secondaryLabelColor
        statsLabel.maximumNumberOfLines = 2
        contentView.addSubview(statsLabel)

        // Ping mode selector
        let pingModeRow = NSStackView()
        pingModeRow.orientation = .horizontal
        pingModeRow.spacing = 10
        pingModeRow.alignment = .centerY
        pingModeRow.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pingModeRow)

        let pingModeLabel = NSTextField(labelWithString: NSLocalizedString("quality.target.label", comment: ""))
        pingModeLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)

        pingModeControl = NSSegmentedControl(labels: [NSLocalizedString("quality.target.internet", comment: ""), NSLocalizedString("quality.target.local", comment: ""), NSLocalizedString("quality.target.custom", comment: "")], trackingMode: .selectOne, target: self, action: #selector(pingModeChanged))
        pingModeControl.selectedSegment = 0

        pingTargetLabel = NSTextField(labelWithString: "→ 8.8.8.8 (Google DNS)")
        pingTargetLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        pingTargetLabel.textColor = .tertiaryLabelColor

        customHostField = NSTextField()
        customHostField.placeholderString = "ex: 192.168.1.100"
        customHostField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        customHostField.translatesAutoresizingMaskIntoConstraints = false
        customHostField.widthAnchor.constraint(equalToConstant: 140).isActive = true
        customHostField.isHidden = true
        customHostField.target = self
        customHostField.action = #selector(customHostChanged)

        let savedCustomHost = UserDefaults.standard.string(forKey: "CustomPingHost") ?? ""
        customHostField.stringValue = savedCustomHost

        let copyStatsButton = NSButton(title: NSLocalizedString("Copier stats", comment: "Copy stats button"), target: self, action: #selector(copyStats))
        copyStatsButton.bezelStyle = .rounded
        copyStatsButton.controlSize = .small
        copyStatsButton.font = NSFont.systemFont(ofSize: 11)

        let historyButton = NSButton(title: NSLocalizedString("Historique 24h", comment: ""), target: self, action: #selector(showHistory))
        historyButton.bezelStyle = .rounded
        historyButton.controlSize = .small
        historyButton.font = NSFont.systemFont(ofSize: 11)

        pingModeRow.addArrangedSubview(pingModeLabel)
        pingModeRow.addArrangedSubview(pingModeControl)
        pingModeRow.addArrangedSubview(pingTargetLabel)
        pingModeRow.addArrangedSubview(customHostField)
        pingModeRow.addArrangedSubview(copyStatsButton)
        pingModeRow.addArrangedSubview(historyButton)

        // Legend
        let legendView = createLegend()
        legendView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(legendView)

        // Graph
        graphView = NetworkGraphView()
        graphView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(graphView)

        NSLayoutConstraint.activate([
            statsLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            statsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            statsLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            pingModeRow.topAnchor.constraint(equalTo: statsLabel.bottomAnchor, constant: 8),
            pingModeRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            pingModeRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            legendView.topAnchor.constraint(equalTo: pingModeRow.bottomAnchor, constant: 8),
            legendView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            legendView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            legendView.heightAnchor.constraint(equalToConstant: 20),

            graphView.topAnchor.constraint(equalTo: legendView.bottomAnchor, constant: 8),
            graphView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            graphView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            graphView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    private func createLegend() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 16

        // Crée un élément de légende (carré de couleur + libellé)
        func dot(color: NSColor, label: String) -> NSView {
            let container = NSStackView()
            container.orientation = .horizontal
            container.spacing = 4

            let colorBox = NSView()
            colorBox.wantsLayer = true
            colorBox.layer?.backgroundColor = color.cgColor
            colorBox.layer?.cornerRadius = 4
            colorBox.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                colorBox.widthAnchor.constraint(equalToConstant: 10),
                colorBox.heightAnchor.constraint(equalToConstant: 10),
            ])

            let text = NSTextField(labelWithString: label)
            text.font = NSFont.systemFont(ofSize: 11)
            text.textColor = .secondaryLabelColor

            container.addArrangedSubview(colorBox)
            container.addArrangedSubview(text)
            return container
        }

        stack.addArrangedSubview(dot(color: .systemGreen, label: NSLocalizedString("quality.legend.latency", comment: "")))
        stack.addArrangedSubview(dot(color: .systemBlue, label: NSLocalizedString("quality.legend.average", comment: "")))
        stack.addArrangedSubview(dot(color: .systemRed, label: NSLocalizedString("quality.legend.loss", comment: "")))
        stack.addArrangedSubview(dot(color: .systemOrange, label: NSLocalizedString("quality.legend.jitter", comment: "")))

        return stack
    }

    @objc private func pingModeChanged(_ sender: NSSegmentedControl) {
        pingMode = PingMode(rawValue: sender.selectedSegment) ?? .internet
        measurements.removeAll()
        graphView.measurements = measurements
        statsLabel.stringValue = NSLocalizedString("quality.status.starting", comment: "")
        customHostField.isHidden = pingMode != .custom
        pingTargetLabel.isHidden = pingMode == .custom
        updatePingTargetLabel()
    }

    @objc private func customHostChanged(_ sender: NSTextField) {
        UserDefaults.standard.set(sender.stringValue, forKey: "CustomPingHost")
        measurements.removeAll()
        graphView.measurements = measurements
        statsLabel.stringValue = NSLocalizedString("quality.status.starting", comment: "")
    }

    private func updatePingTargetLabel() {
        switch pingMode {
        case .internet:
            pingTargetLabel.stringValue = "→ 8.8.8.8 (Google DNS)"
        case .local:
            if let gw = getDefaultGateway() {
                pingTargetLabel.stringValue = "→ \(gw) (\(NSLocalizedString("quality.target.gateway", comment: "")))"
            } else {
                pingTargetLabel.stringValue = "→ \(NSLocalizedString("quality.target.gateway_not_found", comment: ""))"
            }
        case .custom:
            break
        }
    }

    /// Recupere l'adresse de la passerelle par defaut via SCDynamicStore.
    private func getDefaultGateway() -> String? {
        guard let config = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let router = config["Router"] as? String else {
            return nil
        }
        return router
    }

    /// Lance le timer de ping à 1 seconde et effectue une première mesure.
    private func startMeasuring() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.performPing()
        }
        performPing()
    }

    /// Effectue un ping en tâche de fond puis enregistre la mesure sur le thread principal.
    private func performPing() {
        let host: String
        switch pingMode {
        case .internet:
            host = "8.8.8.8"
        case .local:
            guard let gw = getDefaultGateway() else {
                let measurement = PingMeasurement(timestamp: Date(), latency: nil, packetLoss: true)
                measurements.append(measurement)
                if measurements.count > maxPoints { measurements.removeFirst(measurements.count - maxPoints) }
                graphView.measurements = measurements
                updateStats()
                return
            }
            host = gw
        case .custom:
            let customHost = customHostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !customHost.isEmpty else { return }
            host = customHost
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let latency = self?.ping(host: host)
            DispatchQueue.main.async {
                guard let self = self else { return }
                let measurement = PingMeasurement(
                    timestamp: Date(),
                    latency: latency,
                    packetLoss: latency == nil
                )
                self.measurements.append(measurement)
                if self.measurements.count > self.maxPoints {
                    self.measurements.removeFirst(self.measurements.count - self.maxPoints)
                }
                self.graphView.measurements = self.measurements
                self.updateStats()
            }
        }
    }

    /// Envoie un ping ICMP natif (non-privilegie) et mesure la latence.
    /// Supporte IPv4 (ICMP) et IPv6 (ICMPv6).
    private func ping(host: String) -> Double? {
        // Resoudre l'adresse (IPv4 d'abord, IPv6 en fallback)
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_DGRAM
        var infoPtr: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &infoPtr) == 0, let info = infoPtr else { return nil }
        defer { freeaddrinfo(infoPtr) }

        let family = info.pointee.ai_family
        let destAddr = info.pointee.ai_addr
        let destLen = info.pointee.ai_addrlen

        // Creer socket ICMP(v6) non-privilegie
        let proto = family == AF_INET6 ? IPPROTO_ICMPV6 : IPPROTO_ICMP
        let sock = Darwin.socket(family, SOCK_DGRAM, proto)
        guard sock >= 0 else { return nil }
        defer { Darwin.close(sock) }

        // Timeout de reception: 1 seconde
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        // Construire le paquet ICMP Echo Request
        var packet = [UInt8](repeating: 0, count: 64)
        packet[0] = family == AF_INET6 ? 128 : 8  // ICMPv6_ECHO_REQUEST : ICMP_ECHO
        packet[1] = 0  // Code
        let ident = UInt16(ProcessInfo.processInfo.processIdentifier & 0xFFFF)
        packet[4] = UInt8(ident >> 8)
        packet[5] = UInt8(ident & 0xFF)
        let seq = UInt16.random(in: 0...UInt16.max)
        packet[6] = UInt8(seq >> 8)
        packet[7] = UInt8(seq & 0xFF)

        // Checksum (pour IPv4 seulement ; ICMPv6 checksum calculé par le kernel)
        if family == AF_INET {
            var sum: UInt32 = 0
            for i in stride(from: 0, to: packet.count - 1, by: 2) {
                sum += UInt32(packet[i]) << 8 | UInt32(packet[i + 1])
            }
            while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
            let checksum = ~UInt16(sum)
            packet[2] = UInt8(checksum >> 8)
            packet[3] = UInt8(checksum & 0xFF)
        }

        // Envoyer
        let startTime = CFAbsoluteTimeGetCurrent()
        let sent = packet.withUnsafeBytes { bufPtr in
            sendto(sock, bufPtr.baseAddress, bufPtr.count, 0, destAddr, socklen_t(destLen))
        }
        guard sent > 0 else { return nil }

        // Recevoir
        var recvBuf = [UInt8](repeating: 0, count: 1024)
        let recvLen = recv(sock, &recvBuf, recvBuf.count, 0)
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        guard recvLen > 0 else { return nil }

        return elapsed
    }

    /// Calcule et affiche:
    /// - moyenne, min, max de latence (sur les mesures valides)
    /// - jitter: moyenne des différences absolues consécutives
    /// - perte de paquets: pourcentage de mesures en timeout
    /// - qualité: classification simple en fonction des seuils
    private func updateStats() {
        let valid = measurements.compactMap { $0.latency }
        guard !valid.isEmpty else {
            statsLabel.stringValue = NSLocalizedString("quality.status.no_data", comment: "")
            return
        }

        let avg = valid.reduce(0, +) / Double(valid.count)
        let minVal = valid.min() ?? 0
        let maxVal = valid.max() ?? 0
        let lossCount = measurements.filter { $0.packetLoss }.count
        let lossPercent = Double(lossCount) / Double(measurements.count) * 100

        // Jitter = moyenne des différences absolues entre latences consécutives
        var jitter = 0.0
        if valid.count > 1 {
            var diffs: [Double] = []
            for i in 1..<valid.count {
                diffs.append(abs(valid[i] - valid[i - 1]))
            }
            jitter = diffs.reduce(0, +) / Double(diffs.count)
        }

        // Seuils empiriques pour l'étiquette de qualité
        let quality: String
        if lossPercent > 10 || avg > 200 {
            quality = NSLocalizedString("quality.rating.poor", comment: "")
        } else if lossPercent > 2 || avg > 80 || jitter > 30 {
            quality = NSLocalizedString("quality.rating.fair", comment: "")
        } else if avg > 30 || jitter > 10 {
            quality = NSLocalizedString("quality.rating.good", comment: "")
        } else {
            quality = NSLocalizedString("quality.rating.excellent", comment: "")
        }

        statsLabel.stringValue = String(format:
            "Latence: moy %.1f ms | min %.1f ms | max %.1f ms   Jitter: %.1f ms   Perte: %.1f%%   Qualité: %@",
            avg, minVal, maxVal, jitter, lossPercent, quality
        )

        // Sauvegarder un snapshot toutes les 30 mesures (30s)
        snapshotCounter += 1
        if snapshotCounter >= 30 {
            snapshotCounter = 0
            let snapshot = QualitySnapshot(date: Date(), avgLatency: avg, jitter: jitter, lossPercent: lossPercent, quality: quality)
            QualityHistoryStorage.add(snapshot)
        }
    }

    // MARK: - Copier

    @objc private func copyStats() {
        let valid = measurements.compactMap { $0.latency }
        guard !valid.isEmpty else { return }

        let avg = valid.reduce(0, +) / Double(valid.count)
        let minVal = valid.min() ?? 0
        let maxVal = valid.max() ?? 0
        let lossCount = measurements.filter { $0.packetLoss }.count
        let lossPercent = Double(lossCount) / Double(measurements.count) * 100

        var jitter = 0.0
        if valid.count > 1 {
            var diffs: [Double] = []
            for i in 1..<valid.count {
                diffs.append(abs(valid[i] - valid[i - 1]))
            }
            jitter = diffs.reduce(0, +) / Double(diffs.count)
        }

        let text = """
        Mon Réseau — Qualité réseau
        Latence moyenne : \(String(format: "%.1f", avg)) ms
        Latence min : \(String(format: "%.1f", minVal)) ms
        Latence max : \(String(format: "%.1f", maxVal)) ms
        Jitter : \(String(format: "%.1f", jitter)) ms
        Perte de paquets : \(String(format: "%.1f", lossPercent))%
        Mesures : \(measurements.count)
        """

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Historique 24h

    private var historyWindowController: QualityHistoryWindowController?

    @objc private func showHistory() {
        if historyWindowController == nil {
            historyWindowController = QualityHistoryWindowController()
        }
        historyWindowController?.showWindow(nil)
    }

    // Arrête proprement le timer à la fermeture de la fenêtre
    override func close() {
        pingTimer?.invalidate()
        pingTimer = nil
        super.close()
    }

    // Sécurité: invalide le timer si la fenêtre est libérée
    deinit {
        pingTimer?.invalidate()
    }
}

/// Vue personnalisée qui dessine le graphe (grille, latence, jitter, pertes).
class NetworkGraphView: NSView {

    var measurements: [PingMeasurement] = [] {
        didSet {
            needsDisplay = true
            updateAccessibilityValue()
        }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Graphique de qualité réseau")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Graphique de qualité réseau")
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
        let margin = CGFloat(40)
        let graphRect = NSRect(x: margin, y: 10, width: bounds.width - margin - 10, height: bounds.height - 30)

        guard graphRect.contains(point), measurements.count > 1 else { hideTooltip(); return }

        let spacing = graphRect.width / CGFloat(max(measurements.count - 1, 1))
        let index = Int(round((point.x - graphRect.minX) / spacing))
        guard index >= 0, index < measurements.count else { hideTooltip(); return }

        cursorLineX = graphRect.minX + CGFloat(index) * spacing
        needsDisplay = true

        let m = measurements[index]
        var text = "Mesure \(index + 1)/\(measurements.count)"
        if let lat = m.latency { text += String(format: "\nLatence: %.1f ms", lat) }
        else { text += "\nPerte de paquet" }

        if tooltipView == nil {
            let label = NSTextField(labelWithString: "")
            label.font = NSFont.systemFont(ofSize: 10)
            label.backgroundColor = NSColor.windowBackgroundColor
            label.drawsBackground = true
            label.isBezeled = true
            label.bezelStyle = .roundedBezel
            label.maximumNumberOfLines = 3
            addSubview(label)
            tooltipView = label
        }
        tooltipView?.stringValue = text
        tooltipView?.sizeToFit()
        var origin = NSPoint(x: cursorLineX! + 8, y: point.y - 20)
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

    private func updateAccessibilityValue() {
        guard !measurements.isEmpty else {
            setAccessibilityValue("Aucune mesure")
            return
        }
        let latencies = measurements.compactMap(\.latency)
        let avg = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)
        let losses = measurements.filter { $0.latency == nil }.count
        let lossPercent = Double(losses) / Double(measurements.count) * 100
        setAccessibilityValue(String(format: "Latence moyenne %.0f ms, perte %.0f%%", avg, lossPercent))
    }

    // Dessin principal: fond, cadre, grille, zones de perte, aire de jitter, courbe de latence et points
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds

        // Background
        context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        context.fill(rect)

        let margin = CGFloat(40)
        let graphRect = NSRect(
            x: margin, y: 10,
            width: rect.width - margin - 10,
            height: rect.height - 30
        )

        // Graph border
        context.setStrokeColor(NSColor.separatorColor.cgColor)
        context.setLineWidth(1)
        context.stroke(graphRect)

        guard measurements.count > 1 else {
            drawCenteredText(NSLocalizedString("quality.graph.waiting", comment: ""), in: graphRect, context: context)
            return
        }

        let validLatencies = measurements.compactMap { $0.latency }
        guard !validLatencies.isEmpty else {
            drawCenteredText(NSLocalizedString("quality.graph.no_response", comment: ""), in: graphRect, context: context)
            return
        }

        let maxLatency = max(validLatencies.max() ?? 50, 20)
        let yScale = (graphRect.height - 20) / CGFloat(maxLatency)

        // Grid lines and labels
        drawGrid(in: graphRect, maxLatency: maxLatency, context: context)

        let pointSpacing = graphRect.width / CGFloat(max(measurements.count - 1, 1))

        // Draw packet loss markers
        for (i, m) in measurements.enumerated() {
            if m.packetLoss {
                let x = graphRect.minX + CGFloat(i) * pointSpacing
                context.setFillColor(NSColor.systemRed.withAlphaComponent(0.3).cgColor)
                context.fill(CGRect(x: x - 2, y: graphRect.minY, width: 4, height: graphRect.height))
            }
        }

        // Draw jitter as filled area
        drawJitterArea(in: graphRect, pointSpacing: pointSpacing, yScale: yScale, maxLatency: maxLatency, context: context)

        // Draw latency line
        drawLatencyLine(in: graphRect, pointSpacing: pointSpacing, yScale: yScale, maxLatency: maxLatency, context: context)

        // Draw moving average (60s window)
        drawMovingAverage(in: graphRect, pointSpacing: pointSpacing, yScale: yScale, maxLatency: maxLatency, context: context)

        // Draw latency dots
        drawLatencyDots(in: graphRect, pointSpacing: pointSpacing, yScale: yScale, maxLatency: maxLatency, context: context)

        // Cursor line (tooltip hover)
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

    // Dessine des lignes horizontales et étiquettes (ms) selon une graduation adaptée à `maxLatency`
    private func drawGrid(in graphRect: NSRect, maxLatency: Double, context: CGContext) {
        let steps = [5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0]
        let step = steps.first(where: { maxLatency / $0 <= 6 }) ?? 500.0

        context.setStrokeColor(NSColor.separatorColor.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(0.5)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]

        var val = step
        while val < maxLatency {
            let y = graphRect.maxY - CGFloat(val / maxLatency) * (graphRect.height - 20)
            if y > graphRect.minY + 10 {
                context.move(to: CGPoint(x: graphRect.minX, y: y))
                context.addLine(to: CGPoint(x: graphRect.maxX, y: y))
                context.strokePath()

                let label = String(format: "%.0f", val)
                let str = NSAttributedString(string: label, attributes: attrs)
                str.draw(at: NSPoint(x: graphRect.minX - 35, y: y - 6))
            }
            val += step
        }

        // "ms" label
        let msLabel = NSAttributedString(string: "ms", attributes: attrs)
        msLabel.draw(at: NSPoint(x: graphRect.minX - 25, y: graphRect.minY - 2))
    }

    // Trace la courbe de latence en vert
    private func drawLatencyLine(in graphRect: NSRect, pointSpacing: CGFloat, yScale: CGFloat, maxLatency: Double, context: CGContext) {
        let path = CGMutablePath()
        var started = false

        for (i, m) in measurements.enumerated() {
            guard let latency = m.latency else { continue }
            let x = graphRect.minX + CGFloat(i) * pointSpacing
            let y = graphRect.maxY - CGFloat(latency) * yScale

            if !started {
                path.move(to: CGPoint(x: x, y: y))
                started = true
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        context.setStrokeColor(NSColor.systemGreen.cgColor)
        context.setLineWidth(2)
        context.addPath(path)
        context.strokePath()
    }

    // Ajoute des points sur chaque échantillon de latence
    private func drawLatencyDots(in graphRect: NSRect, pointSpacing: CGFloat, yScale: CGFloat, maxLatency: Double, context: CGContext) {
        for (i, m) in measurements.enumerated() {
            guard let latency = m.latency else { continue }
            let x = graphRect.minX + CGFloat(i) * pointSpacing
            let y = graphRect.maxY - CGFloat(latency) * yScale
            let dotRect = CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)
            context.setFillColor(NSColor.systemGreen.cgColor)
            context.fillEllipse(in: dotRect)
        }
    }

    // Trace la moyenne mobile sur 60 secondes en bleu
    private func drawMovingAverage(in graphRect: NSRect, pointSpacing: CGFloat, yScale: CGFloat, maxLatency: Double, context: CGContext) {
        let windowSize = 60 // 60 points = 60 secondes
        guard measurements.count > 1 else { return }

        let path = CGMutablePath()
        var started = false

        for i in 0..<measurements.count {
            // Fenetre glissante: de max(0, i-windowSize+1) a i
            let windowStart = max(0, i - windowSize + 1)
            let window = measurements[windowStart...i]
            let validInWindow = window.compactMap { $0.latency }
            guard !validInWindow.isEmpty else { continue }

            let avg = validInWindow.reduce(0, +) / Double(validInWindow.count)
            let x = graphRect.minX + CGFloat(i) * pointSpacing
            let y = graphRect.maxY - CGFloat(avg) * yScale

            if !started {
                path.move(to: CGPoint(x: x, y: y))
                started = true
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(2)
        context.setLineDash(phase: 0, lengths: [6, 4])
        context.addPath(path)
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
    }

    // Calcule un couloir autour de la latence basé sur le jitter et le remplit en orange translucide
    private func drawJitterArea(in graphRect: NSRect, pointSpacing: CGFloat, yScale: CGFloat, maxLatency: Double, context: CGContext) {
        let validPairs: [(Int, Double, Double)] = {
            var result: [(Int, Double, Double)] = []
            var prevLatency: Double?
            for (i, m) in measurements.enumerated() {
                if let latency = m.latency {
                    if let prev = prevLatency {
                        let jitter = abs(latency - prev)
                        result.append((i, latency, jitter))
                    }
                    prevLatency = latency
                }
            }
            return result
        }()

        guard validPairs.count > 1 else { return }

        let upperPath = CGMutablePath()
        let lowerPath = CGMutablePath()

        for (idx, pair) in validPairs.enumerated() {
            let x = graphRect.minX + CGFloat(pair.0) * pointSpacing
            let baseY = graphRect.maxY - CGFloat(pair.1) * yScale
            let jitterOffset = CGFloat(pair.2) * yScale * 0.5

            if idx == 0 {
                upperPath.move(to: CGPoint(x: x, y: baseY - jitterOffset))
                lowerPath.move(to: CGPoint(x: x, y: baseY + jitterOffset))
            } else {
                upperPath.addLine(to: CGPoint(x: x, y: baseY - jitterOffset))
                lowerPath.addLine(to: CGPoint(x: x, y: baseY + jitterOffset))
            }
        }

        // Combine into a filled area
        let combined = CGMutablePath()
        combined.addPath(upperPath)

        // Reverse lower path
        var lowerPoints: [CGPoint] = []
        lowerPath.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint:
                lowerPoints.append(element.pointee.points[0])
            default: break
            }
        }

        for point in lowerPoints.reversed() {
            combined.addLine(to: point)
        }
        combined.closeSubpath()

        context.setFillColor(NSColor.systemOrange.withAlphaComponent(0.15).cgColor)
        context.addPath(combined)
        context.fillPath()
    }

    // Affiche un texte centré dans un rectangle (état vide)
    private func drawCenteredText(_ text: String, in rect: NSRect, context: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let point = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        str.draw(at: point)
    }
}

// MARK: - QualityHistoryWindowController

class QualityHistoryWindowController: NSWindowController {

    private var historyGraphView: QualityHistoryGraphView!
    private var summaryLabel: NSTextField!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("quality.history.title", comment: "")
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 350)

        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        summaryLabel = NSTextField(wrappingLabelWithString: "")
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        summaryLabel.textColor = .secondaryLabelColor
        contentView.addSubview(summaryLabel)

        // Legend
        let legend = NSStackView()
        legend.orientation = .horizontal
        legend.spacing = 16
        legend.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(legend)

        func dot(color: NSColor, label: String) -> NSView {
            let stack = NSStackView()
            stack.orientation = .horizontal
            stack.spacing = 4
            let box = NSView()
            box.wantsLayer = true
            box.layer?.backgroundColor = color.cgColor
            box.layer?.cornerRadius = 3
            box.translatesAutoresizingMaskIntoConstraints = false
            box.widthAnchor.constraint(equalToConstant: 10).isActive = true
            box.heightAnchor.constraint(equalToConstant: 10).isActive = true
            let text = NSTextField(labelWithString: label)
            text.font = NSFont.systemFont(ofSize: 10)
            text.textColor = .secondaryLabelColor
            stack.addArrangedSubview(box)
            stack.addArrangedSubview(text)
            return stack
        }

        legend.addArrangedSubview(dot(color: .systemGreen, label: "Latence (ms)"))
        legend.addArrangedSubview(dot(color: .systemOrange, label: "Jitter (ms)"))
        legend.addArrangedSubview(dot(color: .systemRed, label: "Perte (%)"))

        historyGraphView = QualityHistoryGraphView()
        historyGraphView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(historyGraphView)

        NSLayoutConstraint.activate([
            summaryLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            summaryLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            summaryLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            legend.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 8),
            legend.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            historyGraphView.topAnchor.constraint(equalTo: legend.bottomAnchor, constant: 8),
            historyGraphView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            historyGraphView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            historyGraphView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        loadHistory()
    }

    private func loadHistory() {
        let snapshots = QualityHistoryStorage.load()
        historyGraphView.snapshots = snapshots

        guard !snapshots.isEmpty else {
            summaryLabel.stringValue = "Aucun historique disponible. Les données sont enregistrées automatiquement lors de l'utilisation de la fenêtre Qualité réseau."
            return
        }

        let avgLat = snapshots.map(\.avgLatency).reduce(0, +) / Double(snapshots.count)
        let avgJitter = snapshots.map(\.jitter).reduce(0, +) / Double(snapshots.count)
        let avgLoss = snapshots.map(\.lossPercent).reduce(0, +) / Double(snapshots.count)
        let oldest = snapshots.last?.date ?? Date()
        let newest = snapshots.first?.date ?? Date()

        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short

        summaryLabel.stringValue = String(format:
            "%d mesures de %@ à %@   |   Latence moy: %.1f ms   Jitter moy: %.1f ms   Perte moy: %.1f%%",
            snapshots.count, df.string(from: oldest), df.string(from: newest), avgLat, avgJitter, avgLoss
        )
    }
}

// MARK: - QualityHistoryGraphView

class QualityHistoryGraphView: NSView {

    var snapshots: [QualitySnapshot] = [] {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSColor.controlBackgroundColor
        bg.setFill()
        dirtyRect.fill()

        let rect = bounds.insetBy(dx: 45, dy: 20)
        guard rect.width > 0, rect.height > 0, snapshots.count > 1 else {
            if snapshots.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 14),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ]
                let str = NSAttributedString(string: "Aucune donnée", attributes: attrs)
                let size = str.size()
                str.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
            }
            return
        }

        // Data is newest-first, reverse for chronological drawing
        let data = Array(snapshots.reversed())

        // Scale: left axis = latency/jitter (ms), right axis = loss (%)
        let maxLatency = max(data.map(\.avgLatency).max() ?? 50, data.map(\.jitter).max() ?? 10, 20)
        let maxLoss = max(data.map(\.lossPercent).max() ?? 5, 1)

        let latencyScale = (rect.height - 10) / CGFloat(maxLatency)
        let lossScale = (rect.height - 10) / CGFloat(maxLoss)
        let step = rect.width / CGFloat(data.count - 1)

        // Grid
        drawGrid(in: rect, maxLatency: maxLatency, maxLoss: maxLoss)

        // Time labels
        drawTimeLabels(in: rect, data: data, step: step)

        // Latency line (green)
        drawLine(data.map(\.avgLatency), in: rect, step: step, scale: latencyScale, color: .systemGreen, lineWidth: 2)

        // Jitter line (orange)
        drawLine(data.map(\.jitter), in: rect, step: step, scale: latencyScale, color: .systemOrange, lineWidth: 1.5)

        // Loss bars (red)
        for (i, snap) in data.enumerated() {
            guard snap.lossPercent > 0 else { continue }
            let x = rect.minX + CGFloat(i) * step
            let h = CGFloat(snap.lossPercent) * lossScale
            let barRect = NSRect(x: x - 1.5, y: rect.minY, width: 3, height: h)
            NSColor.systemRed.withAlphaComponent(0.5).setFill()
            barRect.fill()
        }
    }

    private func drawLine(_ values: [Double], in rect: NSRect, step: CGFloat, scale: CGFloat, color: NSColor, lineWidth: CGFloat) {
        let path = NSBezierPath()
        for (i, val) in values.enumerated() {
            let x = rect.minX + CGFloat(i) * step
            let y = rect.minY + CGFloat(val) * scale
            if i == 0 { path.move(to: NSPoint(x: x, y: y)) }
            else { path.line(to: NSPoint(x: x, y: y)) }
        }
        color.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }

    private func drawGrid(in rect: NSRect, maxLatency: Double, maxLoss: Double) {
        NSColor.separatorColor.setStroke()
        let gridPath = NSBezierPath()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]

        for i in 0...4 {
            let y = rect.minY + rect.height * CGFloat(i) / 4
            gridPath.move(to: NSPoint(x: rect.minX, y: y))
            gridPath.line(to: NSPoint(x: rect.maxX, y: y))

            // Left axis: latency
            let latVal = maxLatency * Double(i) / 4
            String(format: "%.0f", latVal).draw(at: NSPoint(x: 2, y: y - 6), withAttributes: attrs)

            // Right axis: loss
            let lossVal = maxLoss * Double(i) / 4
            let lossStr = String(format: "%.1f%%", lossVal)
            let lossSize = (lossStr as NSString).size(withAttributes: attrs)
            lossStr.draw(at: NSPoint(x: rect.maxX + 4, y: y - 6), withAttributes: attrs)
            _ = lossSize // suppress unused warning
        }
        gridPath.lineWidth = 0.5
        gridPath.stroke()
    }

    private func drawTimeLabels(in rect: NSRect, data: [QualitySnapshot], step: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let df = DateFormatter()
        df.dateFormat = "HH:mm"

        let labelCount = min(8, data.count)
        guard labelCount > 1 else { return }
        let interval = (data.count - 1) / (labelCount - 1)

        for i in 0..<labelCount {
            let idx = min(i * interval, data.count - 1)
            let x = rect.minX + CGFloat(idx) * step
            let label = df.string(from: data[idx].date)
            label.draw(at: NSPoint(x: x - 12, y: rect.minY - 14), withAttributes: attrs)
        }
    }
}


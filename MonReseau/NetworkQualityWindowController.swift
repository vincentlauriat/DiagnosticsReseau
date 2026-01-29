// NetworkQualityWindowController.swift
// Fenêtre d'analyse de la qualité réseau (latence, jitter, perte de paquets)
// Affiche un graphe en temps réel basé sur des pings périodiques (1/s) vers 8.8.8.8.
// Contient aussi `NetworkGraphView` qui dessine le graphe via Core Graphics.

import Cocoa
import Network
// Network pour vérifier l'état global si besoin (NWPathMonitor), ici surtout pour cohérence du module.

/// Mesure individuelle d'un ping.
/// - `timestamp`: date de la mesure
/// - `latency`: latence en millisecondes (nil si timeout)
/// - `packetLoss`: vrai si la réponse n'est pas reçue (timeout)
struct PingMeasurement {
    let timestamp: Date
    let latency: Double?     // ms, nil = timeout
    let packetLoss: Bool
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
    private var measurements: [PingMeasurement] = []
    private let maxPoints = 120 // 2 minutes at 1/s
    private var pingTimer: Timer?

    // Configure la fenetre (taille, titre) puis lance la mesure automatiquement
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mon Réseau — Qualité réseau"
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
        statsLabel = NSTextField(labelWithString: "Démarrage des mesures...")
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        statsLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        statsLabel.textColor = .secondaryLabelColor
        statsLabel.maximumNumberOfLines = 2
        contentView.addSubview(statsLabel)

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

            legendView.topAnchor.constraint(equalTo: statsLabel.bottomAnchor, constant: 8),
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

        stack.addArrangedSubview(dot(color: .systemGreen, label: "Latence (ms)"))
        stack.addArrangedSubview(dot(color: .systemBlue, label: "Moyenne 60s"))
        stack.addArrangedSubview(dot(color: .systemRed, label: "Perte de paquets"))
        stack.addArrangedSubview(dot(color: .systemOrange, label: "Jitter (ms)"))

        return stack
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
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let latency = self?.ping(host: "8.8.8.8")
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
    /// - Parameter host: Hote a pinguer.
    /// - Returns: Latence en millisecondes, ou `nil` en cas de timeout/erreur.
    private func ping(host: String) -> Double? {
        // Resoudre l'adresse
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var infoPtr: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &infoPtr) == 0, let info = infoPtr else { return nil }
        defer { freeaddrinfo(infoPtr) }

        let destAddr = info.pointee.ai_addr
        let destLen = info.pointee.ai_addrlen

        // Creer socket ICMP non-privilegie
        let sock = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard sock >= 0 else { return nil }
        defer { Darwin.close(sock) }

        // Timeout de reception: 1 seconde
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        // Construire le paquet ICMP Echo Request
        var packet = [UInt8](repeating: 0, count: 64)
        packet[0] = 8  // ICMP_ECHO
        packet[1] = 0  // Code
        // Identifier (bytes 4-5)
        let ident = UInt16(ProcessInfo.processInfo.processIdentifier & 0xFFFF)
        packet[4] = UInt8(ident >> 8)
        packet[5] = UInt8(ident & 0xFF)
        // Sequence (bytes 6-7)
        let seq = UInt16.random(in: 0...UInt16.max)
        packet[6] = UInt8(seq >> 8)
        packet[7] = UInt8(seq & 0xFF)

        // Checksum
        var sum: UInt32 = 0
        for i in stride(from: 0, to: packet.count - 1, by: 2) {
            sum += UInt32(packet[i]) << 8 | UInt32(packet[i + 1])
        }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        let checksum = ~UInt16(sum)
        packet[2] = UInt8(checksum >> 8)
        packet[3] = UInt8(checksum & 0xFF)

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
            statsLabel.stringValue = "Aucune mesure disponible"
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
            quality = "Mauvaise"
        } else if lossPercent > 2 || avg > 80 || jitter > 30 {
            quality = "Moyenne"
        } else if avg > 30 || jitter > 10 {
            quality = "Bonne"
        } else {
            quality = "Excellente"
        }

        statsLabel.stringValue = String(format:
            "Latence: moy %.1f ms | min %.1f ms | max %.1f ms   Jitter: %.1f ms   Perte: %.1f%%   Qualité: %@",
            avg, minVal, maxVal, jitter, lossPercent, quality
        )
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
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

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
            drawCenteredText("En attente de données...", in: graphRect, context: context)
            return
        }

        let validLatencies = measurements.compactMap { $0.latency }
        guard !validLatencies.isEmpty else {
            drawCenteredText("Aucune réponse...", in: graphRect, context: context)
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


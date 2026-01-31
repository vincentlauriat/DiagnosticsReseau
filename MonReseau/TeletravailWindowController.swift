// TeletravailWindowController.swift
// Ecran de synthese "Teletravail" : indicateurs WiFi, latence et debit
// avec verdicts par usage (visio, mail, Citrix, transfert, streaming).

import Cocoa
import CoreWLAN
import Network

// MARK: - Modeles

/// Exigences reseau pour un usage donne.
private struct UsageRequirement {
    let name: String
    let icon: String          // SF Symbol
    let minDownload: Double   // Mbps
    let minUpload: Double     // Mbps
    let maxLatency: Double    // ms
    let maxJitter: Double     // ms
    let maxLoss: Double       // %
}

/// Verdict pour un usage.
private enum UsageVerdict {
    case excellent
    case ok
    case degraded
    case insufficient
    case unknown

    var label: String {
        switch self {
        case .excellent: return "Excellent"
        case .ok: return "OK"
        case .degraded: return "Dégradé"
        case .insufficient: return "Insuffisant"
        case .unknown: return "Inconnu"
        }
    }

    var color: NSColor {
        switch self {
        case .excellent: return .systemGreen
        case .ok: return .systemBlue
        case .degraded: return .systemOrange
        case .insufficient: return .systemRed
        case .unknown: return .systemGray
        }
    }
}

// MARK: - Usages de reference

private let usages: [UsageRequirement] = [
    UsageRequirement(name: "Visioconférence", icon: "video.fill",
                     minDownload: 5, minUpload: 3, maxLatency: 100, maxJitter: 30, maxLoss: 2),
    UsageRequirement(name: "Visio HD + Partage écran", icon: "rectangle.inset.filled.and.person.filled",
                     minDownload: 15, minUpload: 8, maxLatency: 50, maxJitter: 20, maxLoss: 1),
    UsageRequirement(name: "Email", icon: "envelope.fill",
                     minDownload: 1, minUpload: 0.5, maxLatency: 300, maxJitter: 100, maxLoss: 5),
    UsageRequirement(name: "Citrix / Bureau distant", icon: "desktopcomputer",
                     minDownload: 5, minUpload: 2, maxLatency: 80, maxJitter: 20, maxLoss: 1),
    UsageRequirement(name: "Transfert de fichiers", icon: "arrow.up.arrow.down.circle.fill",
                     minDownload: 10, minUpload: 5, maxLatency: 500, maxJitter: 100, maxLoss: 3),
    UsageRequirement(name: "Vidéo streaming", icon: "play.rectangle.fill",
                     minDownload: 25, minUpload: 1, maxLatency: 200, maxJitter: 50, maxLoss: 2),
]

// MARK: - Controller

class TeletravailWindowController: NSWindowController {

    // UI — indicateurs
    private var wifiCard: NSView!
    private var wifiStatusDot: NSView!
    private var wifiValueLabel: NSTextField!
    private var wifiDetailLabel: NSTextField!

    private var latencyCard: NSView!
    private var latencyStatusDot: NSView!
    private var latencyValueLabel: NSTextField!
    private var latencyDetailLabel: NSTextField!

    private var speedCard: NSView!
    private var speedStatusDot: NSView!
    private var speedValueLabel: NSTextField!
    private var speedDetailLabel: NSTextField!

    // UI — usages
    private var usageRows: [(dot: NSView, label: NSTextField)] = []

    // UI — verdict global
    private var globalVerdictDot: NSView!
    private var globalVerdictLabel: NSTextField!
    private var globalVerdictDetail: NSTextField!

    // Etat
    private var refreshTimer: Timer?
    private var pingLatencies: [Double] = []
    private let maxPingSamples = 30  // 30 secondes de mesures

    // Dernier debit connu
    private var lastDownload: Double = 0
    private var lastUpload: Double = 0
    private var hasSpeedData = false

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mon Réseau — Télétravail"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 480)

        self.init(window: window)
        setupUI()
        loadLastSpeedTest()
        startMeasuring()
    }

    // MARK: - UI

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        // Le documentView doit avoir la meme largeur que le scrollView
        NSLayoutConstraint.activate([
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
        ])

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 16
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -20),
        ])

        // Titre
        let title = NSTextField(labelWithString: "Télétravail")
        title.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        stack.addArrangedSubview(title)

        let subtitle = NSTextField(labelWithString: "Diagnostic en temps réel de votre connexion pour le travail à distance.")
        subtitle.font = NSFont.systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        stack.addArrangedSubview(subtitle)

        // --- Indicateurs ---
        let cardsRow = NSStackView()
        cardsRow.orientation = .horizontal
        cardsRow.spacing = 12
        cardsRow.distribution = .fillEqually
        cardsRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(cardsRow)
        cardsRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let (wc, wd, wv, wdet) = makeIndicatorCard(title: "WiFi", icon: "wifi", value: "—", detail: "")
        wifiCard = wc; wifiStatusDot = wd; wifiValueLabel = wv; wifiDetailLabel = wdet
        cardsRow.addArrangedSubview(wc)

        let (lc, ld, lv, ldet) = makeIndicatorCard(title: "Latence", icon: "gauge.with.dots.needle.50percent", value: "—", detail: "")
        latencyCard = lc; latencyStatusDot = ld; latencyValueLabel = lv; latencyDetailLabel = ldet
        cardsRow.addArrangedSubview(lc)

        let (sc, sd, sv, sdet) = makeIndicatorCard(title: "Débit", icon: "speedometer", value: "—", detail: "")
        speedCard = sc; speedStatusDot = sd; speedValueLabel = sv; speedDetailLabel = sdet
        cardsRow.addArrangedSubview(sc)

        // --- Separator ---
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // --- Compatibilite usages ---
        let usagesTitle = NSTextField(labelWithString: "Compatibilité des usages")
        usagesTitle.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        stack.addArrangedSubview(usagesTitle)

        for usage in usages {
            let (row, dot, verdictLabel) = makeUsageRow(usage: usage)
            usageRows.append((dot: dot, label: verdictLabel))
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        // --- Separator ---
        let sep2 = NSBox()
        sep2.boxType = .separator
        sep2.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(sep2)
        sep2.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // --- Verdict global ---
        let globalRow = NSStackView()
        globalRow.orientation = .horizontal
        globalRow.spacing = 10
        globalRow.alignment = .centerY
        globalRow.translatesAutoresizingMaskIntoConstraints = false

        globalVerdictDot = NSView()
        globalVerdictDot.wantsLayer = true
        globalVerdictDot.layer?.cornerRadius = 8
        globalVerdictDot.layer?.backgroundColor = NSColor.systemGray.cgColor
        globalVerdictDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            globalVerdictDot.widthAnchor.constraint(equalToConstant: 16),
            globalVerdictDot.heightAnchor.constraint(equalToConstant: 16),
        ])

        let globalTextStack = NSStackView()
        globalTextStack.orientation = .vertical
        globalTextStack.spacing = 2
        globalTextStack.alignment = .leading

        globalVerdictLabel = NSTextField(labelWithString: "Analyse en cours…")
        globalVerdictLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)

        globalVerdictDetail = NSTextField(labelWithString: "")
        globalVerdictDetail.font = NSFont.systemFont(ofSize: 11)
        globalVerdictDetail.textColor = .secondaryLabelColor

        globalTextStack.addArrangedSubview(globalVerdictLabel)
        globalTextStack.addArrangedSubview(globalVerdictDetail)

        globalRow.addArrangedSubview(globalVerdictDot)
        globalRow.addArrangedSubview(globalTextStack)

        stack.addArrangedSubview(globalRow)
        globalRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Note
        let note = NSTextField(labelWithString: "Les indicateurs WiFi et latence sont mesurés en temps réel. Le débit utilise le dernier test effectué (fenêtre Test de débit).")
        note.font = NSFont.systemFont(ofSize: 10)
        note.textColor = .tertiaryLabelColor
        note.maximumNumberOfLines = 2
        note.preferredMaxLayoutWidth = 560
        stack.addArrangedSubview(note)
    }

    private func makeIndicatorCard(title: String, icon: String, value: String, detail: String) -> (NSView, NSView, NSTextField, NSTextField) {
        let card = ThemedCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.heightAnchor.constraint(equalToConstant: 90).isActive = true

        let vstack = NSStackView()
        vstack.orientation = .vertical
        vstack.spacing = 4
        vstack.alignment = .leading
        vstack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(vstack)

        NSLayoutConstraint.activate([
            vstack.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            vstack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            vstack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            vstack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -10),
        ])

        // Titre + dot
        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.spacing = 6
        headerRow.alignment = .centerY

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = NSColor.systemGray.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),
        ])

        let iconView = NSImageView()
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: title) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            iconView.image = img.withSymbolConfiguration(config)
        }
        iconView.contentTintColor = .secondaryLabelColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor

        headerRow.addArrangedSubview(dot)
        headerRow.addArrangedSubview(iconView)
        headerRow.addArrangedSubview(titleLabel)

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .semibold)

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = NSFont.systemFont(ofSize: 10)
        detailLabel.textColor = .tertiaryLabelColor
        detailLabel.maximumNumberOfLines = 2

        vstack.addArrangedSubview(headerRow)
        vstack.addArrangedSubview(valueLabel)
        vstack.addArrangedSubview(detailLabel)

        return (card, dot, valueLabel, detailLabel)
    }

    private func makeUsageRow(usage: UsageRequirement) -> (NSView, NSView, NSTextField) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = NSColor.systemGray.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),
        ])

        let iconView = NSImageView()
        if let img = NSImage(systemSymbolName: usage.icon, accessibilityDescription: usage.name) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            iconView.image = img.withSymbolConfiguration(config)
        }
        iconView.contentTintColor = .labelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 20).isActive = true

        let nameLabel = NSTextField(labelWithString: usage.name)
        nameLabel.font = NSFont.systemFont(ofSize: 13)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let verdictLabel = NSTextField(labelWithString: "—")
        verdictLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        verdictLabel.alignment = .right
        verdictLabel.setContentHuggingPriority(.required, for: .horizontal)
        verdictLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true

        row.addArrangedSubview(dot)
        row.addArrangedSubview(iconView)
        row.addArrangedSubview(nameLabel)
        row.addArrangedSubview(verdictLabel)

        return (row, dot, verdictLabel)
    }

    // MARK: - Mesures

    private func startMeasuring() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshWiFi()
            self?.performPing()
            self?.evaluateUsages()
        }
        // Premier tick immédiat
        refreshWiFi()
        performPing()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.evaluateUsages()
        }
    }

    private func loadLastSpeedTest() {
        let history = SpeedTestHistoryStorage.load()
        if let last = history.first {
            lastDownload = last.downloadMbps
            lastUpload = last.uploadMbps
            hasSpeedData = true
            updateSpeedCard()
        } else {
            speedValueLabel.stringValue = "Aucun test"
            speedDetailLabel.stringValue = "Lancez un test de débit"
            speedStatusDot.layer?.backgroundColor = NSColor.systemGray.cgColor
        }
    }

    private func refreshWiFi() {
        guard let client = CWWiFiClient.shared().interface(),
              let ssid = client.ssid(), !ssid.isEmpty else {
            wifiValueLabel.stringValue = "Déconnecté"
            wifiDetailLabel.stringValue = ""
            wifiStatusDot.layer?.backgroundColor = NSColor.systemRed.cgColor
            return
        }

        let rssi = client.rssiValue()
        let txRate = client.transmitRate()

        wifiValueLabel.stringValue = "\(rssi) dBm"

        var detail = ssid
        if let ch = client.wlanChannel() {
            switch ch.channelBand {
            case .band2GHz: detail += " · 2.4 GHz"
            case .band5GHz: detail += " · 5 GHz"
            case .band6GHz: detail += " · 6 GHz"
            default: break
            }
        }
        if txRate > 0 { detail += " · \(Int(txRate)) Mbps" }
        wifiDetailLabel.stringValue = detail

        let color: NSColor
        if rssi >= -50 { color = .systemGreen }
        else if rssi >= -70 { color = .systemOrange }
        else { color = .systemRed }
        wifiStatusDot.layer?.backgroundColor = color.cgColor
    }

    private func performPing() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let latency = self?.ping(host: "8.8.8.8")
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let lat = latency {
                    self.pingLatencies.append(lat)
                    if self.pingLatencies.count > self.maxPingSamples {
                        self.pingLatencies.removeFirst(self.pingLatencies.count - self.maxPingSamples)
                    }
                }
                self.updateLatencyCard(lastPing: latency)
            }
        }
    }

    private func updateLatencyCard(lastPing: Double?) {
        guard !pingLatencies.isEmpty else {
            latencyValueLabel.stringValue = "—"
            latencyDetailLabel.stringValue = ""
            latencyStatusDot.layer?.backgroundColor = NSColor.systemGray.cgColor
            return
        }

        let avg = pingLatencies.reduce(0, +) / Double(pingLatencies.count)
        let jitter: Double
        if pingLatencies.count > 1 {
            var diffs: [Double] = []
            for i in 1..<pingLatencies.count {
                diffs.append(abs(pingLatencies[i] - pingLatencies[i - 1]))
            }
            jitter = diffs.reduce(0, +) / Double(diffs.count)
        } else {
            jitter = 0
        }

        if let last = lastPing {
            latencyValueLabel.stringValue = String(format: "%.0f ms", last)
        } else {
            latencyValueLabel.stringValue = "Timeout"
        }
        latencyDetailLabel.stringValue = String(format: "Moy: %.0f ms · Jitter: %.1f ms", avg, jitter)

        let color: NSColor
        if avg <= 30 && jitter <= 10 { color = .systemGreen }
        else if avg <= 80 && jitter <= 30 { color = .systemOrange }
        else { color = .systemRed }
        latencyStatusDot.layer?.backgroundColor = color.cgColor
    }

    private func updateSpeedCard() {
        speedValueLabel.stringValue = String(format: "↓ %.0f  ↑ %.0f Mbps", lastDownload, lastUpload)
        let history = SpeedTestHistoryStorage.load()
        if let last = history.first {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            speedDetailLabel.stringValue = "Test du \(formatter.string(from: last.date))"
        }

        let color: NSColor
        if lastDownload >= 50 { color = .systemGreen }
        else if lastDownload >= 10 { color = .systemBlue }
        else if lastDownload >= 5 { color = .systemOrange }
        else { color = .systemRed }
        speedStatusDot.layer?.backgroundColor = color.cgColor
    }

    // MARK: - Evaluation des usages

    private func evaluateUsages() {
        let avg = pingLatencies.isEmpty ? Double.infinity : pingLatencies.reduce(0, +) / Double(pingLatencies.count)
        let jitter: Double
        if pingLatencies.count > 1 {
            var diffs: [Double] = []
            for i in 1..<pingLatencies.count {
                diffs.append(abs(pingLatencies[i] - pingLatencies[i - 1]))
            }
            jitter = diffs.reduce(0, +) / Double(diffs.count)
        } else {
            jitter = 0
        }
        let loss = 0.0 // pas de mesure de perte dans ce contexte simplifié

        var verdicts: [UsageVerdict] = []

        for (i, usage) in usages.enumerated() {
            let verdict: UsageVerdict

            if pingLatencies.isEmpty && !hasSpeedData {
                verdict = .unknown
            } else {
                let dlOk = !hasSpeedData || lastDownload >= usage.minDownload
                let ulOk = !hasSpeedData || lastUpload >= usage.minUpload
                let latOk = pingLatencies.isEmpty || avg <= usage.maxLatency
                let jitOk = pingLatencies.isEmpty || jitter <= usage.maxJitter
                let lossOk = loss <= usage.maxLoss

                let allOk = dlOk && ulOk && latOk && jitOk && lossOk

                if !allOk {
                    verdict = .insufficient
                } else {
                    // Verifier si "excellent" (x2 les seuils)
                    let dlExc = !hasSpeedData || lastDownload >= usage.minDownload * 2
                    let ulExc = !hasSpeedData || lastUpload >= usage.minUpload * 2
                    let latExc = pingLatencies.isEmpty || avg <= usage.maxLatency * 0.5
                    let jitExc = pingLatencies.isEmpty || jitter <= usage.maxJitter * 0.5

                    if dlExc && ulExc && latExc && jitExc {
                        verdict = .excellent
                    } else {
                        // Verifier si "degradé" (proche des limites : > 80% du seuil)
                        let dlClose = hasSpeedData && lastDownload < usage.minDownload * 1.3
                        let ulClose = hasSpeedData && lastUpload < usage.minUpload * 1.3
                        let latClose = !pingLatencies.isEmpty && avg > usage.maxLatency * 0.7
                        let jitClose = !pingLatencies.isEmpty && jitter > usage.maxJitter * 0.7

                        if dlClose || ulClose || latClose || jitClose {
                            verdict = .degraded
                        } else {
                            verdict = .ok
                        }
                    }
                }
            }

            verdicts.append(verdict)
            usageRows[i].dot.layer?.backgroundColor = verdict.color.cgColor
            usageRows[i].label.stringValue = verdict.label
            usageRows[i].label.textColor = verdict.color
        }

        // Verdict global
        updateGlobalVerdict(verdicts)
    }

    private func updateGlobalVerdict(_ verdicts: [UsageVerdict]) {
        if verdicts.allSatisfy({ $0 == .unknown }) {
            globalVerdictDot.layer?.backgroundColor = NSColor.systemGray.cgColor
            globalVerdictLabel.stringValue = "Analyse en cours…"
            globalVerdictDetail.stringValue = "En attente de données suffisantes."
            return
        }

        let hasInsufficient = verdicts.contains(.insufficient)
        let hasDegraded = verdicts.contains(.degraded)
        let allExcellent = verdicts.allSatisfy({ $0 == .excellent || $0 == .unknown })

        if hasInsufficient {
            globalVerdictDot.layer?.backgroundColor = NSColor.systemRed.cgColor
            globalVerdictLabel.stringValue = "Connexion insuffisante"
            let problematic = zip(usages, verdicts).filter { $0.1 == .insufficient }.map { $0.0.name }
            globalVerdictDetail.stringValue = "Usages impactés : \(problematic.joined(separator: ", "))"
        } else if hasDegraded {
            globalVerdictDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
            globalVerdictLabel.stringValue = "Connexion dégradée"
            let problematic = zip(usages, verdicts).filter { $0.1 == .degraded }.map { $0.0.name }
            globalVerdictDetail.stringValue = "À surveiller : \(problematic.joined(separator: ", "))"
        } else if allExcellent {
            globalVerdictDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
            globalVerdictLabel.stringValue = "Connexion excellente"
            globalVerdictDetail.stringValue = "Votre réseau est parfaitement adapté au télétravail."
        } else {
            globalVerdictDot.layer?.backgroundColor = NSColor.systemBlue.cgColor
            globalVerdictLabel.stringValue = "Connexion adaptée au télétravail"
            globalVerdictDetail.stringValue = "Tous les usages courants sont fonctionnels."
        }
    }

    // MARK: - Ping ICMP (meme implementation que NetworkQualityWindowController)

    private func ping(host: String) -> Double? {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_DGRAM
        var infoPtr: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &infoPtr) == 0, let info = infoPtr else { return nil }
        defer { freeaddrinfo(infoPtr) }

        let family = info.pointee.ai_family
        let destAddr = info.pointee.ai_addr
        let destLen = info.pointee.ai_addrlen

        let proto = family == AF_INET6 ? IPPROTO_ICMPV6 : IPPROTO_ICMP
        let sock = Darwin.socket(family, SOCK_DGRAM, proto)
        guard sock >= 0 else { return nil }
        defer { Darwin.close(sock) }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var packet = [UInt8](repeating: 0, count: 64)
        packet[0] = family == AF_INET6 ? 128 : 8
        packet[1] = 0
        let ident = UInt16(ProcessInfo.processInfo.processIdentifier & 0xFFFF)
        packet[4] = UInt8(ident >> 8)
        packet[5] = UInt8(ident & 0xFF)
        let seq = UInt16.random(in: 0...UInt16.max)
        packet[6] = UInt8(seq >> 8)
        packet[7] = UInt8(seq & 0xFF)

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

        let startTime = CFAbsoluteTimeGetCurrent()
        let sent = packet.withUnsafeBytes { bufPtr in
            sendto(sock, bufPtr.baseAddress, bufPtr.count, 0, destAddr, socklen_t(destLen))
        }
        guard sent > 0 else { return nil }

        var recvBuf = [UInt8](repeating: 0, count: 1024)
        let received = recv(sock, &recvBuf, recvBuf.count, 0)
        guard received > 0 else { return nil }

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        return elapsed
    }

    // MARK: - Lifecycle

    override func close() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        super.close()
    }

    deinit {
        refreshTimer?.invalidate()
    }
}

// MARK: - Carte adaptative (apparence)

private class ThemedCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
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

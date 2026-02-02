// TeletravailWindowController.swift
// Ecran de synthese "Teletravail" : indicateurs WiFi, latence et debit
// avec verdicts par usage (visio, mail, Citrix, transfert, streaming).

import Cocoa
import CoreWLAN
import Network
import UniformTypeIdentifiers

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
        case .excellent: return NSLocalizedString("teletravail.verdict.excellent", comment: "")
        case .ok: return NSLocalizedString("teletravail.verdict.ok", comment: "")
        case .degraded: return NSLocalizedString("teletravail.verdict.degraded", comment: "")
        case .insufficient: return NSLocalizedString("teletravail.verdict.insufficient", comment: "")
        case .unknown: return NSLocalizedString("teletravail.verdict.unknown", comment: "")
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
    UsageRequirement(name: NSLocalizedString("teletravail.usage.visio", comment: ""), icon: "video.fill",
                     minDownload: 5, minUpload: 3, maxLatency: 100, maxJitter: 30, maxLoss: 2),
    UsageRequirement(name: NSLocalizedString("teletravail.usage.visiohd", comment: ""), icon: "rectangle.inset.filled.and.person.filled",
                     minDownload: 15, minUpload: 8, maxLatency: 50, maxJitter: 20, maxLoss: 1),
    UsageRequirement(name: NSLocalizedString("teletravail.usage.email", comment: ""), icon: "envelope.fill",
                     minDownload: 1, minUpload: 0.5, maxLatency: 300, maxJitter: 100, maxLoss: 5),
    UsageRequirement(name: NSLocalizedString("teletravail.usage.citrix", comment: ""), icon: "desktopcomputer",
                     minDownload: 5, minUpload: 2, maxLatency: 80, maxJitter: 20, maxLoss: 1),
    UsageRequirement(name: NSLocalizedString("teletravail.usage.transfer", comment: ""), icon: "arrow.up.arrow.down.circle.fill",
                     minDownload: 10, minUpload: 5, maxLatency: 500, maxJitter: 100, maxLoss: 3),
    UsageRequirement(name: NSLocalizedString("teletravail.usage.streaming", comment: ""), icon: "play.rectangle.fill",
                     minDownload: 25, minUpload: 1, maxLatency: 200, maxJitter: 50, maxLoss: 2),
    UsageRequirement(name: NSLocalizedString("teletravail.usage.gaming", comment: ""), icon: "gamecontroller.fill",
                     minDownload: 25, minUpload: 5, maxLatency: 30, maxJitter: 10, maxLoss: 0.5),
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
        window.title = NSLocalizedString("teletravail.title", comment: "")
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
        let title = NSTextField(labelWithString: NSLocalizedString("teletravail.heading", comment: ""))
        title.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        stack.addArrangedSubview(title)

        let subtitle = NSTextField(labelWithString: NSLocalizedString("teletravail.subtitle", comment: ""))
        subtitle.font = NSFont.systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        stack.addArrangedSubview(subtitle)

        let buttonsRow = NSStackView()
        buttonsRow.orientation = .horizontal
        buttonsRow.spacing = 8

        let copyReportButton = NSButton(title: NSLocalizedString("teletravail.button.copy_report", comment: ""), target: self, action: #selector(copyReport))
        copyReportButton.bezelStyle = .rounded
        copyReportButton.controlSize = .small

        let exportPDFButton = NSButton(title: NSLocalizedString("teletravail.button.exportpdf", comment: ""), target: self, action: #selector(exportPDF))
        exportPDFButton.bezelStyle = .rounded
        exportPDFButton.controlSize = .small

        buttonsRow.addArrangedSubview(copyReportButton)
        buttonsRow.addArrangedSubview(exportPDFButton)
        stack.addArrangedSubview(buttonsRow)

        // --- Indicateurs ---
        let cardsRow = NSStackView()
        cardsRow.orientation = .horizontal
        cardsRow.spacing = 12
        cardsRow.distribution = .fillEqually
        cardsRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(cardsRow)
        cardsRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let (wc, wd, wv, wdet) = makeIndicatorCard(title: NSLocalizedString("teletravail.card.wifi", comment: ""), icon: "wifi", value: "—", detail: "")
        wifiCard = wc; wifiStatusDot = wd; wifiValueLabel = wv; wifiDetailLabel = wdet
        wc.setAccessibilityRole(.group)
        wc.setAccessibilityLabel(NSLocalizedString("teletravail.accessibility.wifi", comment: ""))
        cardsRow.addArrangedSubview(wc)

        let (lc, ld, lv, ldet) = makeIndicatorCard(title: NSLocalizedString("teletravail.card.latency", comment: ""), icon: "gauge.with.dots.needle.50percent", value: "—", detail: "")
        latencyCard = lc; latencyStatusDot = ld; latencyValueLabel = lv; latencyDetailLabel = ldet
        lc.setAccessibilityRole(.group)
        lc.setAccessibilityLabel(NSLocalizedString("teletravail.accessibility.latency", comment: ""))
        cardsRow.addArrangedSubview(lc)

        let (sc, sd, sv, sdet) = makeIndicatorCard(title: NSLocalizedString("teletravail.card.speed", comment: ""), icon: "speedometer", value: "—", detail: "")
        speedCard = sc; speedStatusDot = sd; speedValueLabel = sv; speedDetailLabel = sdet
        sc.setAccessibilityRole(.group)
        sc.setAccessibilityLabel(NSLocalizedString("teletravail.accessibility.speed", comment: ""))
        cardsRow.addArrangedSubview(sc)

        // --- Separator ---
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // --- Compatibilite usages ---
        let usagesTitle = NSTextField(labelWithString: NSLocalizedString("teletravail.usages.title", comment: ""))
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

        globalVerdictLabel = NSTextField(labelWithString: NSLocalizedString("teletravail.verdict.analyzing", comment: ""))
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
        let note = NSTextField(labelWithString: NSLocalizedString("teletravail.note", comment: ""))
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
            speedValueLabel.stringValue = NSLocalizedString("teletravail.speed.no_test", comment: "")
            speedDetailLabel.stringValue = NSLocalizedString("teletravail.speed.run_test", comment: "")
            speedStatusDot.layer?.backgroundColor = NSColor.systemGray.cgColor
        }
    }

    private func refreshWiFi() {
        guard let client = CWWiFiClient.shared().interface(),
              let ssid = client.ssid(), !ssid.isEmpty else {
            wifiValueLabel.stringValue = NSLocalizedString("teletravail.wifi.disconnected", comment: "")
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
            latencyValueLabel.stringValue = NSLocalizedString("teletravail.latency.timeout", comment: "")
        }
        latencyDetailLabel.stringValue = String(format: NSLocalizedString("teletravail.latency.detail_format", comment: ""), avg, jitter)

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
            speedDetailLabel.stringValue = String(format: NSLocalizedString("teletravail.speed.date_format", comment: ""), formatter.string(from: last.date))
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
            globalVerdictLabel.stringValue = NSLocalizedString("teletravail.verdict.analyzing", comment: "")
            globalVerdictDetail.stringValue = NSLocalizedString("teletravail.verdict.waiting", comment: "")
            return
        }

        let hasInsufficient = verdicts.contains(.insufficient)
        let hasDegraded = verdicts.contains(.degraded)
        let allExcellent = verdicts.allSatisfy({ $0 == .excellent || $0 == .unknown })

        if hasInsufficient {
            globalVerdictDot.layer?.backgroundColor = NSColor.systemRed.cgColor
            globalVerdictLabel.stringValue = NSLocalizedString("teletravail.global.insufficient", comment: "")
            let problematic = zip(usages, verdicts).filter { $0.1 == .insufficient }.map { $0.0.name }
            globalVerdictDetail.stringValue = String(format: NSLocalizedString("teletravail.global.impacted_usages", comment: ""), problematic.joined(separator: ", "))
        } else if hasDegraded {
            globalVerdictDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
            globalVerdictLabel.stringValue = NSLocalizedString("teletravail.global.degraded", comment: "")
            let problematic = zip(usages, verdicts).filter { $0.1 == .degraded }.map { $0.0.name }
            globalVerdictDetail.stringValue = String(format: NSLocalizedString("teletravail.global.watch_usages", comment: ""), problematic.joined(separator: ", "))
        } else if allExcellent {
            globalVerdictDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
            globalVerdictLabel.stringValue = NSLocalizedString("teletravail.global.excellent", comment: "")
            globalVerdictDetail.stringValue = NSLocalizedString("teletravail.global.excellent_detail", comment: "")
        } else {
            globalVerdictDot.layer?.backgroundColor = NSColor.systemBlue.cgColor
            globalVerdictLabel.stringValue = NSLocalizedString("teletravail.global.ok", comment: "")
            globalVerdictDetail.stringValue = NSLocalizedString("teletravail.global.ok_detail", comment: "")
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

    // MARK: - Copier rapport

    @objc private func copyReport() {
        var text = NSLocalizedString("teletravail.report.header", comment: "") + "\n"
        text += String(repeating: "═", count: 50) + "\n\n"

        // WiFi
        text += "\(NSLocalizedString("teletravail.report.wifi", comment: "")) \(wifiValueLabel.stringValue)\n"
        if !wifiDetailLabel.stringValue.isEmpty {
            text += "  \(wifiDetailLabel.stringValue)\n"
        }

        // Latence
        text += "\(NSLocalizedString("teletravail.report.latency", comment: "")) \(latencyValueLabel.stringValue)\n"
        if !latencyDetailLabel.stringValue.isEmpty {
            text += "  \(latencyDetailLabel.stringValue)\n"
        }

        // Debit
        text += "\(NSLocalizedString("teletravail.report.speed", comment: "")) \(speedValueLabel.stringValue)\n"
        if !speedDetailLabel.stringValue.isEmpty {
            text += "  \(speedDetailLabel.stringValue)\n"
        }

        text += "\n\(NSLocalizedString("teletravail.report.usages", comment: ""))\n"
        text += String(repeating: "─", count: 40) + "\n"
        for (i, usage) in usages.enumerated() {
            let verdict = usageRows[i].label.stringValue
            text += "  \(usage.name.padding(toLength: 30, withPad: " ", startingAt: 0)) \(verdict)\n"
        }

        text += "\n\(NSLocalizedString("teletravail.report.global_verdict", comment: "")) \(globalVerdictLabel.stringValue)\n"
        if !globalVerdictDetail.stringValue.isEmpty {
            text += "\(globalVerdictDetail.stringValue)\n"
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Export PDF

    @objc private func exportPDF() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType.pdf]
        savePanel.nameFieldStringValue = "MonReseau-Diagnostic.pdf"
        savePanel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = savePanel.url, let self = self else { return }
            self.generatePDF(to: url)
        }
    }

    private func generatePDF(to url: URL) {
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let margin: CGFloat = 50
        let contentWidth = pageWidth - margin * 2

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return }
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }

        context.beginPDFPage(nil)

        // Set up NSGraphicsContext for NSAttributedString drawing
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        // Y position tracks from top, but CG origin is bottom-left
        // We'll use a helper that converts top-down Y to CG Y
        var cursorY = pageHeight - margin  // start from top

        // --- Title ---
        let titleFont = NSFont.systemFont(ofSize: 20, weight: .bold)
        let titleStr = NSAttributedString(string: "Mon Réseau — Diagnostic", attributes: [
            .font: titleFont,
            .foregroundColor: NSColor.black
        ])
        cursorY -= titleStr.size().height
        titleStr.draw(at: NSPoint(x: margin, y: cursorY))

        // Date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        let dateFont = NSFont.systemFont(ofSize: 11)
        let dateStr = NSAttributedString(string: dateFormatter.string(from: Date()), attributes: [
            .font: dateFont,
            .foregroundColor: NSColor.darkGray
        ])
        cursorY -= dateStr.size().height + 4
        dateStr.draw(at: NSPoint(x: margin, y: cursorY))

        cursorY -= 20

        // --- Section: Indicateurs ---
        cursorY = drawSectionTitle(NSLocalizedString("teletravail.pdf.section.indicators", comment: "Indicateurs"), at: cursorY, margin: margin, context: context)
        cursorY -= 6

        // WiFi indicator
        cursorY = drawIndicatorRow(
            label: NSLocalizedString("teletravail.card.wifi", comment: ""),
            value: wifiValueLabel.stringValue,
            detail: wifiDetailLabel.stringValue,
            dotColor: colorFromDotLayer(wifiStatusDot),
            at: cursorY, margin: margin, context: context
        )

        // Latency indicator
        cursorY = drawIndicatorRow(
            label: NSLocalizedString("teletravail.card.latency", comment: ""),
            value: latencyValueLabel.stringValue,
            detail: latencyDetailLabel.stringValue,
            dotColor: colorFromDotLayer(latencyStatusDot),
            at: cursorY, margin: margin, context: context
        )

        // Speed indicator
        cursorY = drawIndicatorRow(
            label: NSLocalizedString("teletravail.card.speed", comment: ""),
            value: speedValueLabel.stringValue,
            detail: speedDetailLabel.stringValue,
            dotColor: colorFromDotLayer(speedStatusDot),
            at: cursorY, margin: margin, context: context
        )

        cursorY -= 16

        // --- Section: Compatibilite des usages ---
        cursorY = drawSectionTitle(NSLocalizedString("teletravail.usages.title", comment: ""), at: cursorY, margin: margin, context: context)
        cursorY -= 8

        // Table header
        let headerFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let headerColor = NSColor.darkGray
        let colUsageX = margin
        let colVerdictX = margin + contentWidth * 0.55
        let colDetailX = margin + contentWidth * 0.75

        let hUsage = NSAttributedString(string: NSLocalizedString("teletravail.pdf.col.usage", comment: "Usage"), attributes: [.font: headerFont, .foregroundColor: headerColor])
        let hVerdict = NSAttributedString(string: NSLocalizedString("teletravail.pdf.col.verdict", comment: "Verdict"), attributes: [.font: headerFont, .foregroundColor: headerColor])

        cursorY -= hUsage.size().height
        hUsage.draw(at: NSPoint(x: colUsageX + 16, y: cursorY))
        hVerdict.draw(at: NSPoint(x: colVerdictX, y: cursorY))
        cursorY -= 6

        // Draw separator line
        context.setStrokeColor(NSColor.lightGray.cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: margin, y: cursorY))
        context.addLine(to: CGPoint(x: margin + contentWidth, y: cursorY))
        context.strokePath()
        cursorY -= 6

        let rowFont = NSFont.systemFont(ofSize: 11)
        let verdictFont = NSFont.systemFont(ofSize: 11, weight: .medium)

        for (i, usage) in usages.enumerated() {
            let verdictText = usageRows[i].label.stringValue
            let dotColor = colorFromDotLayer(usageRows[i].dot)

            let nameStr = NSAttributedString(string: usage.name, attributes: [.font: rowFont, .foregroundColor: NSColor.black])
            let verdictStr = NSAttributedString(string: verdictText, attributes: [.font: verdictFont, .foregroundColor: dotColor])

            let rowH = max(nameStr.size().height, verdictStr.size().height)
            cursorY -= rowH + 2

            // Colored dot
            let dotSize: CGFloat = 8
            let dotY = cursorY + (rowH - dotSize) / 2
            context.setFillColor(dotColor.cgColor)
            context.fillEllipse(in: CGRect(x: colUsageX, y: dotY, width: dotSize, height: dotSize))

            nameStr.draw(at: NSPoint(x: colUsageX + 16, y: cursorY))
            verdictStr.draw(at: NSPoint(x: colVerdictX, y: cursorY))

            cursorY -= 4
        }

        cursorY -= 16

        // --- Section: Verdict global ---
        cursorY = drawSectionTitle(NSLocalizedString("teletravail.pdf.section.global_verdict", comment: "Verdict global"), at: cursorY, margin: margin, context: context)
        cursorY -= 8

        let globalColor = colorFromDotLayer(globalVerdictDot)
        let globalFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let globalStr = NSAttributedString(string: globalVerdictLabel.stringValue, attributes: [.font: globalFont, .foregroundColor: globalColor])
        let globalDetailStr = NSAttributedString(string: globalVerdictDetail.stringValue, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.darkGray])

        // Background rounded rect
        let bgHeight: CGFloat = 44
        cursorY -= bgHeight
        let bgRect = CGRect(x: margin, y: cursorY, width: contentWidth, height: bgHeight)
        context.setFillColor(globalColor.withAlphaComponent(0.1).cgColor)
        let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.addPath(bgPath)
        context.fillPath()

        // Dot
        let gDotSize: CGFloat = 12
        context.setFillColor(globalColor.cgColor)
        context.fillEllipse(in: CGRect(x: margin + 12, y: cursorY + (bgHeight - gDotSize) / 2, width: gDotSize, height: gDotSize))

        // Text
        globalStr.draw(at: NSPoint(x: margin + 30, y: cursorY + bgHeight - 6 - globalStr.size().height))
        globalDetailStr.draw(at: NSPoint(x: margin + 30, y: cursorY + 6))

        cursorY -= 30

        // --- Footer ---
        let footerFont = NSFont.systemFont(ofSize: 9)
        let footerStr = NSAttributedString(string: NSLocalizedString("teletravail.pdf.footer", comment: "Généré par Mon Réseau"), attributes: [
            .font: footerFont,
            .foregroundColor: NSColor.gray
        ])
        footerStr.draw(at: NSPoint(x: margin, y: margin - 10))

        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()

        pdfData.write(to: url, atomically: true)
    }

    private func drawSectionTitle(_ title: String, at y: CGFloat, margin: CGFloat, context: CGContext) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let str = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: NSColor.black])
        let h = str.size().height
        let newY = y - h
        str.draw(at: NSPoint(x: margin, y: newY))
        return newY
    }

    private func drawIndicatorRow(label: String, value: String, detail: String, dotColor: NSColor, at y: CGFloat, margin: CGFloat, context: CGContext) -> CGFloat {
        var curY = y

        let labelFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        let detailFont = NSFont.systemFont(ofSize: 9)

        let labelStr = NSAttributedString(string: label, attributes: [.font: labelFont, .foregroundColor: NSColor.darkGray])
        let valueStr = NSAttributedString(string: value, attributes: [.font: valueFont, .foregroundColor: NSColor.black])
        let detailStr = NSAttributedString(string: detail, attributes: [.font: detailFont, .foregroundColor: NSColor.gray])

        // Dot + label
        curY -= labelStr.size().height
        let dotSize: CGFloat = 8
        let dotY = curY + (labelStr.size().height - dotSize) / 2
        context.setFillColor(dotColor.cgColor)
        context.fillEllipse(in: CGRect(x: margin, y: dotY, width: dotSize, height: dotSize))
        labelStr.draw(at: NSPoint(x: margin + 14, y: curY))

        // Value
        curY -= valueStr.size().height + 2
        valueStr.draw(at: NSPoint(x: margin + 14, y: curY))

        // Detail
        if !detail.isEmpty {
            curY -= detailStr.size().height + 1
            detailStr.draw(at: NSPoint(x: margin + 14, y: curY))
        }

        curY -= 8
        return curY
    }

    private func colorFromDotLayer(_ view: NSView) -> NSColor {
        guard let cgColor = view.layer?.backgroundColor else { return .gray }
        return NSColor(cgColor: cgColor) ?? .gray
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

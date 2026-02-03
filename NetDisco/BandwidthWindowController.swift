// BandwidthWindowController.swift
// NetDisco
//
// Moniteur de bande passante en temps réel. Affiche le débit entrant/sortant
// par interface via getifaddrs() avec un graphe Core Graphics (120 points, 2 min).

import Cocoa

class BandwidthWindowController: NSWindowController {

    private var timer: Timer?
    private var graphView: BandwidthGraphView!
    private var inRateLabel: NSTextField!
    private var outRateLabel: NSTextField!
    private var totalInLabel: NSTextField!
    private var totalOutLabel: NSTextField!

    private var previousBytes: (inBytes: UInt64, outBytes: UInt64, date: Date)?
    private var sessionStartBytes: (inBytes: UInt64, outBytes: UInt64)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("bandwidth.title", comment: "")
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 450, height: 300)
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Stats bar
        let statsBar = NSView()
        statsBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statsBar)

        func makeStatLabel(icon: String, color: NSColor) -> (NSTextField, NSTextField) {
            let iconLabel = NSTextField(labelWithString: icon)
            iconLabel.font = NSFont.systemFont(ofSize: 14)
            iconLabel.textColor = color
            iconLabel.translatesAutoresizingMaskIntoConstraints = false
            statsBar.addSubview(iconLabel)

            let valueLabel = NSTextField(labelWithString: "— ")
            valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
            valueLabel.translatesAutoresizingMaskIntoConstraints = false
            statsBar.addSubview(valueLabel)
            return (iconLabel, valueLabel)
        }

        let (inIcon, inVal) = makeStatLabel(icon: "↓", color: .systemBlue)
        inRateLabel = inVal
        let (outIcon, outVal) = makeStatLabel(icon: "↑", color: .systemOrange)
        outRateLabel = outVal

        let totalLabel = NSTextField(labelWithString: NSLocalizedString("bandwidth.session_total", comment: ""))
        totalLabel.font = NSFont.systemFont(ofSize: 11)
        totalLabel.textColor = .secondaryLabelColor
        totalLabel.translatesAutoresizingMaskIntoConstraints = false
        statsBar.addSubview(totalLabel)

        totalInLabel = NSTextField(labelWithString: "↓ —")
        totalInLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        totalInLabel.textColor = .secondaryLabelColor
        totalInLabel.translatesAutoresizingMaskIntoConstraints = false
        statsBar.addSubview(totalInLabel)

        totalOutLabel = NSTextField(labelWithString: "↑ —")
        totalOutLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        totalOutLabel.textColor = .secondaryLabelColor
        totalOutLabel.translatesAutoresizingMaskIntoConstraints = false
        statsBar.addSubview(totalOutLabel)

        // Copy button
        let copyButton = NSButton(title: NSLocalizedString("bandwidth.copy", comment: ""), target: self, action: #selector(copyStats))
        copyButton.bezelStyle = .rounded
        copyButton.controlSize = .small
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        statsBar.addSubview(copyButton)

        NSLayoutConstraint.activate([
            inIcon.leadingAnchor.constraint(equalTo: statsBar.leadingAnchor, constant: 16),
            inIcon.centerYAnchor.constraint(equalTo: statsBar.centerYAnchor, constant: -8),
            inVal.leadingAnchor.constraint(equalTo: inIcon.trailingAnchor, constant: 4),
            inVal.centerYAnchor.constraint(equalTo: inIcon.centerYAnchor),

            outIcon.leadingAnchor.constraint(equalTo: inVal.trailingAnchor, constant: 24),
            outIcon.centerYAnchor.constraint(equalTo: inIcon.centerYAnchor),
            outVal.leadingAnchor.constraint(equalTo: outIcon.trailingAnchor, constant: 4),
            outVal.centerYAnchor.constraint(equalTo: outIcon.centerYAnchor),

            totalLabel.leadingAnchor.constraint(equalTo: statsBar.leadingAnchor, constant: 16),
            totalLabel.centerYAnchor.constraint(equalTo: statsBar.centerYAnchor, constant: 10),
            totalInLabel.leadingAnchor.constraint(equalTo: totalLabel.trailingAnchor, constant: 8),
            totalInLabel.centerYAnchor.constraint(equalTo: totalLabel.centerYAnchor),
            totalOutLabel.leadingAnchor.constraint(equalTo: totalInLabel.trailingAnchor, constant: 12),
            totalOutLabel.centerYAnchor.constraint(equalTo: totalLabel.centerYAnchor),

            copyButton.trailingAnchor.constraint(equalTo: statsBar.trailingAnchor, constant: -16),
            copyButton.centerYAnchor.constraint(equalTo: statsBar.centerYAnchor),
        ])

        // Graph
        graphView = BandwidthGraphView()
        graphView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(graphView)

        NSLayoutConstraint.activate([
            statsBar.topAnchor.constraint(equalTo: contentView.topAnchor),
            statsBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statsBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statsBar.heightAnchor.constraint(equalToConstant: 60),

            graphView.topAnchor.constraint(equalTo: statsBar.bottomAnchor),
            graphView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            graphView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            graphView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        startMonitoring()
    }

    private func startMonitoring() {
        timer?.invalidate()
        previousBytes = nil
        sessionStartBytes = nil
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sample()
        }
        sample()
    }

    private func sample() {
        guard let current = readInterfaceBytes() else { return }

        if sessionStartBytes == nil {
            sessionStartBytes = current
        }

        if let prev = previousBytes {
            let elapsed = Date().timeIntervalSince(prev.date)
            guard elapsed > 0 else { return }
            let inRate = Double(current.0 &- prev.inBytes) / elapsed
            let outRate = Double(current.1 &- prev.outBytes) / elapsed

            inRateLabel.stringValue = formatRate(inRate)
            outRateLabel.stringValue = formatRate(outRate)

            graphView.addSample(inRate: inRate, outRate: outRate)

            if let start = sessionStartBytes {
                totalInLabel.stringValue = "↓ " + formatBytes(current.0 &- start.0)
                totalOutLabel.stringValue = "↑ " + formatBytes(current.1 &- start.1)
            }
        }
        previousBytes = (current.0, current.1, Date())
    }

    private func readInterfaceBytes() -> (UInt64, UInt64)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let addr = cursor {
            defer { cursor = addr.pointee.ifa_next }
            guard let sa = addr.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: addr.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("utun") || name.hasPrefix("ppp") else { continue }
            if let data = addr.pointee.ifa_data {
                let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                totalIn += UInt64(networkData.ifi_ibytes)
                totalOut += UInt64(networkData.ifi_obytes)
            }
        }
        return (totalIn, totalOut)
    }

    private func formatRate(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 { return String(format: "%.0f o/s", bytesPerSec) }
        if bytesPerSec < 1024 * 1024 { return String(format: "%.0f Ko/s", bytesPerSec / 1024) }
        return String(format: "%.1f Mo/s", bytesPerSec / (1024 * 1024))
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let b = Double(bytes)
        if b < 1024 { return String(format: "%.0f o", b) }
        if b < 1024 * 1024 { return String(format: "%.1f Ko", b / 1024) }
        if b < 1024 * 1024 * 1024 { return String(format: "%.1f Mo", b / (1024 * 1024)) }
        return String(format: "%.2f Go", b / (1024 * 1024 * 1024))
    }

    @objc private func copyStats() {
        var text = NSLocalizedString("bandwidth.title", comment: "") + "\n"
        text += "↓ " + inRateLabel.stringValue + "  ↑ " + outRateLabel.stringValue + "\n"
        text += totalInLabel.stringValue + "  " + totalOutLabel.stringValue
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - BandwidthGraphView

class BandwidthGraphView: NSView {
    private let maxPoints = 120
    private var inSamples: [Double] = []
    private var outSamples: [Double] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Graphique de bande passante")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Graphique de bande passante")
    }

    func addSample(inRate: Double, outRate: Double) {
        inSamples.append(inRate)
        outSamples.append(outRate)
        if inSamples.count > maxPoints { inSamples.removeFirst() }
        if outSamples.count > maxPoints { outSamples.removeFirst() }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSColor.controlBackgroundColor
        bg.setFill()
        dirtyRect.fill()

        let rect = bounds.insetBy(dx: 40, dy: 20)
        guard rect.width > 0, rect.height > 0, !inSamples.isEmpty else { return }

        // Scale
        let allMax = max((inSamples + outSamples).max() ?? 1, 1024)
        let scale = rect.height / CGFloat(allMax)

        // Grid lines
        NSColor.separatorColor.setStroke()
        let gridPath = NSBezierPath()
        for i in 0...4 {
            let y = rect.minY + rect.height * CGFloat(i) / 4
            gridPath.move(to: NSPoint(x: rect.minX, y: y))
            gridPath.line(to: NSPoint(x: rect.maxX, y: y))

            let value = allMax * Double(i) / 4
            let label = formatAxisLabel(value)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            label.draw(at: NSPoint(x: 2, y: y - 6), withAttributes: attrs)
        }
        gridPath.lineWidth = 0.5
        gridPath.stroke()

        // Draw filled area + line for download (blue)
        drawSeries(inSamples, in: rect, scale: scale, color: NSColor.systemBlue.withAlphaComponent(0.3), lineColor: .systemBlue)
        // Draw filled area + line for upload (orange)
        drawSeries(outSamples, in: rect, scale: scale, color: NSColor.systemOrange.withAlphaComponent(0.3), lineColor: .systemOrange)

        // Legend
        let legendY = bounds.maxY - 16
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.labelColor,
        ]
        NSColor.systemBlue.setFill()
        NSRect(x: rect.maxX - 140, y: legendY - 3, width: 10, height: 10).fill()
        ("↓ " + NSLocalizedString("bandwidth.download", comment: "")).draw(at: NSPoint(x: rect.maxX - 126, y: legendY - 5), withAttributes: attrs)

        NSColor.systemOrange.setFill()
        NSRect(x: rect.maxX - 60, y: legendY - 3, width: 10, height: 10).fill()
        ("↑ " + NSLocalizedString("bandwidth.upload", comment: "")).draw(at: NSPoint(x: rect.maxX - 46, y: legendY - 5), withAttributes: attrs)
    }

    private func drawSeries(_ samples: [Double], in rect: NSRect, scale: CGFloat, color: NSColor, lineColor: NSColor) {
        guard samples.count > 1 else { return }
        let step = rect.width / CGFloat(maxPoints - 1)
        let offset = maxPoints - samples.count

        let path = NSBezierPath()
        let fillPath = NSBezierPath()
        fillPath.move(to: NSPoint(x: rect.minX + CGFloat(offset) * step, y: rect.minY))

        for (i, val) in samples.enumerated() {
            let x = rect.minX + CGFloat(offset + i) * step
            let y = rect.minY + CGFloat(val) * scale
            if i == 0 {
                path.move(to: NSPoint(x: x, y: y))
            } else {
                path.line(to: NSPoint(x: x, y: y))
            }
            fillPath.line(to: NSPoint(x: x, y: y))
        }

        let lastX = rect.minX + CGFloat(offset + samples.count - 1) * step
        fillPath.line(to: NSPoint(x: lastX, y: rect.minY))
        fillPath.close()

        color.setFill()
        fillPath.fill()
        lineColor.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    private func formatAxisLabel(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 { return String(format: "%.0f o/s", bytesPerSec) }
        if bytesPerSec < 1024 * 1024 { return String(format: "%.0f Ko/s", bytesPerSec / 1024) }
        return String(format: "%.1f Mo/s", bytesPerSec / (1024 * 1024))
    }
}

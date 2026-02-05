// MultiTargetGraphView.swift
// NetDisco
//
// Graphe multi-séries réutilisable pour afficher jusqu'à 5 cibles simultanément.
// Utilisé par Multi-ping, Dashboard et autres visualisations comparatives.

import Cocoa

// MARK: - Data Model

struct GraphTarget {
    let id: String
    let name: String
    let color: NSColor
    var samples: [Double?] = []  // nil = timeout/no data

    var validSamples: [Double] {
        samples.compactMap { $0 }
    }

    var avgValue: Double {
        let valid = validSamples
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0, +) / Double(valid.count)
    }

    var minValue: Double {
        validSamples.min() ?? 0
    }

    var maxValue: Double {
        validSamples.max() ?? 0
    }

    var lossPercent: Double {
        guard !samples.isEmpty else { return 0 }
        let lost = samples.filter { $0 == nil }.count
        return Double(lost) / Double(samples.count) * 100
    }
}

// MARK: - MultiTargetGraphView

class MultiTargetGraphView: NSView {

    // Configuration
    let maxPoints = 120  // 2 minutes à 1 Hz
    var showLegend = true
    var showGrid = true
    var showTooltip = true
    var yAxisLabel = "ms"
    var minYValue: Double = 0
    var maxYValueOverride: Double? = nil  // nil = auto-scale

    // Couleurs prédéfinies pour jusqu'à 5 cibles
    static let defaultColors: [NSColor] = [
        .systemBlue,
        .systemOrange,
        .systemGreen,
        .systemPurple,
        .systemPink
    ]

    // Données
    private(set) var targets: [GraphTarget] = []

    // Tooltip
    private var cursorX: CGFloat? = nil
    private var tooltipWindow: NSWindow?
    private var trackingArea: NSTrackingArea?

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupAccessibility()
        setupTracking()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupAccessibility()
        setupTracking()
    }

    private func setupAccessibility() {
        setAccessibilityRole(.image)
        setAccessibilityLabel(NSLocalizedString("multiping.graph.accessibility", comment: "Graphique multi-cibles"))
    }

    private func setupTracking() {
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - Public API

    func setTargets(_ newTargets: [GraphTarget]) {
        targets = newTargets
        needsDisplay = true
        updateAccessibilityValue()
    }

    func addTarget(id: String, name: String, color: NSColor? = nil) {
        let colorToUse = color ?? Self.defaultColors[targets.count % Self.defaultColors.count]
        let target = GraphTarget(id: id, name: name, color: colorToUse)
        targets.append(target)
        needsDisplay = true
    }

    func removeTarget(id: String) {
        targets.removeAll { $0.id == id }
        needsDisplay = true
    }

    func addSample(targetId: String, value: Double?) {
        guard let idx = targets.firstIndex(where: { $0.id == targetId }) else { return }
        targets[idx].samples.append(value)
        if targets[idx].samples.count > maxPoints {
            targets[idx].samples.removeFirst()
        }
        needsDisplay = true
        updateAccessibilityValue()
    }

    func addSamples(_ samples: [(targetId: String, value: Double?)]) {
        for sample in samples {
            if let idx = targets.firstIndex(where: { $0.id == sample.targetId }) {
                targets[idx].samples.append(sample.value)
                if targets[idx].samples.count > maxPoints {
                    targets[idx].samples.removeFirst()
                }
            }
        }
        needsDisplay = true
        updateAccessibilityValue()
    }

    func clearAll() {
        for i in targets.indices {
            targets[i].samples.removeAll()
        }
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Background
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()

        let graphRect = calculateGraphRect()
        guard graphRect.width > 0, graphRect.height > 0 else { return }

        // Calculate scale
        let allValues = targets.flatMap { $0.validSamples }
        var maxValue = maxYValueOverride ?? (allValues.max() ?? 100)
        maxValue = max(maxValue, 1)  // Éviter division par zéro

        let scale = graphRect.height / CGFloat(maxValue - minYValue)

        // Draw grid
        if showGrid {
            drawGrid(in: graphRect, maxValue: maxValue)
        }

        // Draw each series
        for target in targets {
            drawSeries(target, in: graphRect, scale: scale, minY: minYValue)
        }

        // Draw legend
        if showLegend && !targets.isEmpty {
            drawLegend(in: graphRect)
        }

        // Draw cursor line if hovering
        if let x = cursorX, x >= graphRect.minX && x <= graphRect.maxX {
            drawCursorLine(at: x, in: graphRect)
        }
    }

    private func calculateGraphRect() -> NSRect {
        var rect = bounds
        rect.origin.x += 50  // Espace pour l'axe Y
        rect.origin.y += 20  // Espace en bas
        rect.size.width -= 60
        rect.size.height -= (showLegend ? 50 : 30)
        return rect
    }

    private func drawGrid(in rect: NSRect, maxValue: Double) {
        NSColor.separatorColor.setStroke()
        let gridPath = NSBezierPath()

        // Lignes horizontales (5 niveaux)
        for i in 0...4 {
            let y = rect.minY + rect.height * CGFloat(i) / 4
            gridPath.move(to: NSPoint(x: rect.minX, y: y))
            gridPath.line(to: NSPoint(x: rect.maxX, y: y))

            // Labels axe Y
            let value = minYValue + (maxValue - minYValue) * Double(i) / 4
            let label = formatAxisValue(value)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: rect.minX - size.width - 4, y: y - 6), withAttributes: attrs)
        }

        // Lignes verticales (temps)
        for i in 0...4 {
            let x = rect.minX + rect.width * CGFloat(i) / 4
            gridPath.move(to: NSPoint(x: x, y: rect.minY))
            gridPath.line(to: NSPoint(x: x, y: rect.maxY))

            // Labels temps (en secondes depuis maintenant)
            let seconds = (4 - i) * 30  // 0, 30, 60, 90, 120
            let timeLabel = seconds == 0 ? NSLocalizedString("graph.now", comment: "") : "-\(seconds)s"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
            let size = timeLabel.size(withAttributes: attrs)
            timeLabel.draw(at: NSPoint(x: x - size.width / 2, y: rect.minY - 16), withAttributes: attrs)
        }

        gridPath.lineWidth = 0.5
        gridPath.stroke()
    }

    private func drawSeries(_ target: GraphTarget, in rect: NSRect, scale: CGFloat, minY: Double) {
        guard target.samples.count > 1 else { return }

        let step = rect.width / CGFloat(maxPoints - 1)
        let offset = maxPoints - target.samples.count

        let path = NSBezierPath()
        var lastValidPoint: NSPoint? = nil

        for (i, value) in target.samples.enumerated() {
            let x = rect.minX + CGFloat(offset + i) * step

            if let val = value {
                let y = rect.minY + CGFloat(val - minY) * scale
                let point = NSPoint(x: x, y: min(y, rect.maxY))

                if let last = lastValidPoint {
                    // Dessiner depuis le dernier point valide
                    path.move(to: last)
                    path.line(to: point)
                } else if i > 0 {
                    path.move(to: point)
                }
                lastValidPoint = point
            } else {
                // Timeout - marquer avec un petit X rouge
                let markerRect = NSRect(x: x - 2, y: rect.minY - 2, width: 4, height: 4)
                NSColor.systemRed.withAlphaComponent(0.5).setFill()
                NSBezierPath(ovalIn: markerRect).fill()
                lastValidPoint = nil
            }
        }

        target.color.setStroke()
        path.lineWidth = 2.0
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func drawLegend(in graphRect: NSRect) {
        let legendY = bounds.maxY - 18
        var legendX = graphRect.minX

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.labelColor
        ]

        for target in targets {
            // Carré de couleur
            target.color.setFill()
            NSRect(x: legendX, y: legendY - 3, width: 10, height: 10).fill()

            // Nom + stats
            let text = "\(target.name)"
            legendX += 14
            text.draw(at: NSPoint(x: legendX, y: legendY - 5), withAttributes: attrs)
            legendX += text.size(withAttributes: attrs).width + 20
        }
    }

    private func drawCursorLine(at x: CGFloat, in rect: NSRect) {
        // Ligne verticale pointillée
        NSColor.labelColor.withAlphaComponent(0.5).setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x, y: rect.minY))
        path.line(to: NSPoint(x: x, y: rect.maxY))
        path.lineWidth = 1.0
        path.setLineDash([4, 4], count: 2, phase: 0)
        path.stroke()

        // Points sur chaque courbe
        let step = rect.width / CGFloat(maxPoints - 1)

        for target in targets {
            let offset = maxPoints - target.samples.count
            let index = Int((x - rect.minX) / step) - offset

            if index >= 0 && index < target.samples.count, let value = target.samples[index] {
                let y = rect.minY + CGFloat(value - minYValue) * (rect.height / CGFloat((maxYValueOverride ?? (targets.flatMap { $0.validSamples }.max() ?? 100)) - minYValue))

                // Point
                let pointRect = NSRect(x: x - 4, y: y - 4, width: 8, height: 8)
                NSColor.controlBackgroundColor.setFill()
                NSBezierPath(ovalIn: pointRect).fill()
                target.color.setStroke()
                NSBezierPath(ovalIn: pointRect).stroke()
            }
        }
    }

    private func formatAxisValue(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        return String(format: "%.0f", value)
    }

    // MARK: - Mouse Tracking

    override func mouseEntered(with event: NSEvent) {
        cursorX = convert(event.locationInWindow, from: nil).x
        needsDisplay = true
        showTooltipWindow(for: event)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        cursorX = point.x
        needsDisplay = true
        updateTooltip(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        cursorX = nil
        needsDisplay = true
        hideTooltipWindow()
    }

    private func showTooltipWindow(for event: NSEvent) {
        guard showTooltip else { return }

        let tooltipView = NSTextField(labelWithString: "")
        tooltipView.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        tooltipView.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
        tooltipView.isBordered = true
        tooltipView.bezelStyle = .roundedBezel

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 150, height: 80),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .floating
        window.contentView = tooltipView

        tooltipWindow = window
        updateTooltip(for: event)
    }

    private func updateTooltip(for event: NSEvent) {
        guard let window = tooltipWindow,
              let label = window.contentView as? NSTextField else { return }

        let point = convert(event.locationInWindow, from: nil)
        let graphRect = calculateGraphRect()

        guard point.x >= graphRect.minX && point.x <= graphRect.maxX else {
            window.orderOut(nil)
            return
        }

        let step = graphRect.width / CGFloat(maxPoints - 1)
        var lines: [String] = []

        for target in targets {
            let offset = maxPoints - target.samples.count
            let index = Int((point.x - graphRect.minX) / step) - offset

            if index >= 0 && index < target.samples.count {
                if let value = target.samples[index] {
                    lines.append("\(target.name): \(String(format: "%.1f", value)) \(yAxisLabel)")
                } else {
                    lines.append("\(target.name): " + NSLocalizedString("graph.timeout", comment: "Timeout"))
                }
            }
        }

        if lines.isEmpty {
            window.orderOut(nil)
            return
        }

        label.stringValue = lines.joined(separator: "\n")
        label.sizeToFit()

        var windowFrame = window.frame
        windowFrame.size = NSSize(width: label.frame.width + 16, height: label.frame.height + 8)

        // Position près du curseur
        let screenPoint = self.window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
        windowFrame.origin = NSPoint(x: screenPoint.x + 15, y: screenPoint.y - windowFrame.height - 5)

        window.setFrame(windowFrame, display: true)
        window.orderFront(nil)
    }

    private func hideTooltipWindow() {
        tooltipWindow?.orderOut(nil)
        tooltipWindow = nil
    }

    // MARK: - Accessibility

    private func updateAccessibilityValue() {
        var description = ""
        for target in targets {
            if !target.validSamples.isEmpty {
                description += "\(target.name): \(String(format: "%.1f", target.avgValue)) \(yAxisLabel) "
            }
        }
        setAccessibilityValue(description)
    }
}

// ReportsWindowController.swift
// NetDisco
//
// Fenêtre de rapports et visualisations :
//   - Timeline : périodes connecté/déconnecté sur 7/30 jours
//   - Comparaison : performances entre profils réseau
//   - Rapports : résumés hebdomadaires et mensuels

import Cocoa

// MARK: - Weekly/Monthly Reports

enum TrendDirection: String, Codable {
    case improving
    case stable
    case degrading

    var label: String {
        switch self {
        case .improving: return NSLocalizedString("reports.trend.improving", comment: "")
        case .stable: return NSLocalizedString("reports.trend.stable", comment: "")
        case .degrading: return NSLocalizedString("reports.trend.degrading", comment: "")
        }
    }

    var symbol: String {
        switch self {
        case .improving: return "↗"
        case .stable: return "→"
        case .degrading: return "↘"
        }
    }

    var color: NSColor {
        switch self {
        case .improving: return .systemGreen
        case .stable: return .systemBlue
        case .degrading: return .systemOrange
        }
    }
}

struct WeeklyReport: Codable {
    let weekStart: Date
    let avgLatency: Double
    let avgJitter: Double
    let avgPacketLoss: Double
    let avgUptimePercent: Double
    let totalTestCount: Int
    let degradationCount: Int
    let avgDownload: Double?
    let avgUpload: Double?
    let trend: TrendDirection
}

struct MonthlyReport: Codable {
    let monthStart: Date
    let avgLatency: Double
    let avgJitter: Double
    let avgPacketLoss: Double
    let avgUptimePercent: Double
    let avgDownload: Double?
    let avgUpload: Double?
    let trend: TrendDirection
}

// MARK: - Report Storage Extension

extension ScheduledTestStorage {
    static let weeklyKey = "WeeklyReports"
    static let monthlyKey = "MonthlyReports"
    static let maxWeekly = 12  // 3 mois
    static let maxMonthly = 12 // 1 an

    static func loadWeeklyReports() -> [WeeklyReport] {
        guard let data = UserDefaults.standard.data(forKey: weeklyKey),
              let reports = try? JSONDecoder().decode([WeeklyReport].self, from: data) else {
            return []
        }
        return reports
    }

    static func saveWeeklyReports(_ reports: [WeeklyReport]) {
        let trimmed = Array(reports.suffix(maxWeekly))
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: weeklyKey)
        }
    }

    static func addWeeklyReport(_ report: WeeklyReport) {
        var reports = loadWeeklyReports()
        reports.append(report)
        saveWeeklyReports(reports)
    }

    static func loadMonthlyReports() -> [MonthlyReport] {
        guard let data = UserDefaults.standard.data(forKey: monthlyKey),
              let reports = try? JSONDecoder().decode([MonthlyReport].self, from: data) else {
            return []
        }
        return reports
    }

    static func saveMonthlyReports(_ reports: [MonthlyReport]) {
        let trimmed = Array(reports.suffix(maxMonthly))
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: monthlyKey)
        }
    }

    static func addMonthlyReport(_ report: MonthlyReport) {
        var reports = loadMonthlyReports()
        reports.append(report)
        saveMonthlyReports(reports)
    }

    /// Compile un rapport hebdomadaire à partir des rapports journaliers.
    static func compileWeeklyReport() -> WeeklyReport? {
        let dailyReports = loadReports()
        let calendar = Calendar.current

        // Trouver le début de la semaine dernière
        let today = calendar.startOfDay(for: Date())
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: today) else { return nil }

        let weekReports = dailyReports.filter { $0.date >= weekAgo && $0.date < today }
        guard !weekReports.isEmpty else { return nil }

        let latencies = weekReports.map { $0.avgLatency }
        let jitters = weekReports.map { $0.avgJitter }
        let losses = weekReports.map { $0.avgPacketLoss }
        let uptimes = weekReports.map { $0.uptimePercent }
        let testCount = weekReports.reduce(0) { $0 + $1.testCount }
        let degradations = weekReports.reduce(0) { $0 + $1.degradationCount }

        // Calculer la tendance basée sur la comparaison première/seconde moitié
        let midpoint = weekReports.count / 2
        let trend: TrendDirection
        if midpoint > 0 {
            let firstHalfAvg = weekReports.prefix(midpoint).map { $0.avgLatency }.reduce(0, +) / Double(midpoint)
            let secondHalfAvg = weekReports.suffix(midpoint).map { $0.avgLatency }.reduce(0, +) / Double(midpoint)
            if secondHalfAvg < firstHalfAvg * 0.9 {
                trend = .improving
            } else if secondHalfAvg > firstHalfAvg * 1.1 {
                trend = .degrading
            } else {
                trend = .stable
            }
        } else {
            trend = .stable
        }

        // Récupérer les données de speed test de la semaine
        let speedHistory = SpeedTestHistoryStorage.load()
        let weekSpeeds = speedHistory.filter { $0.date >= weekAgo && $0.date < today }
        let avgDown: Double? = weekSpeeds.isEmpty ? nil : weekSpeeds.map { $0.downloadMbps }.reduce(0, +) / Double(weekSpeeds.count)
        let avgUp: Double? = weekSpeeds.isEmpty ? nil : weekSpeeds.map { $0.uploadMbps }.reduce(0, +) / Double(weekSpeeds.count)

        return WeeklyReport(
            weekStart: weekAgo,
            avgLatency: latencies.reduce(0, +) / Double(latencies.count),
            avgJitter: jitters.reduce(0, +) / Double(jitters.count),
            avgPacketLoss: losses.reduce(0, +) / Double(losses.count),
            avgUptimePercent: uptimes.reduce(0, +) / Double(uptimes.count),
            totalTestCount: testCount,
            degradationCount: degradations,
            avgDownload: avgDown,
            avgUpload: avgUp,
            trend: trend
        )
    }

    /// Compile un rapport mensuel à partir des rapports hebdomadaires.
    static func compileMonthlyReport() -> MonthlyReport? {
        let weeklyReports = loadWeeklyReports()
        let calendar = Calendar.current

        // Trouver le début du mois dernier
        guard let monthAgo = calendar.date(byAdding: .month, value: -1, to: Date()) else { return nil }
        let startOfLastMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: monthAgo))!
        let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!

        let monthReports = weeklyReports.filter { $0.weekStart >= startOfLastMonth && $0.weekStart < startOfThisMonth }
        guard !monthReports.isEmpty else { return nil }

        let latencies = monthReports.map { $0.avgLatency }
        let jitters = monthReports.map { $0.avgJitter }
        let losses = monthReports.map { $0.avgPacketLoss }
        let uptimes = monthReports.map { $0.avgUptimePercent }

        // Tendance basée sur première vs dernière semaine
        let trend: TrendDirection
        if monthReports.count >= 2 {
            let first = monthReports.first!.avgLatency
            let last = monthReports.last!.avgLatency
            if last < first * 0.9 {
                trend = .improving
            } else if last > first * 1.1 {
                trend = .degrading
            } else {
                trend = .stable
            }
        } else {
            trend = .stable
        }

        // Moyennes de débit
        let downloads = monthReports.compactMap { $0.avgDownload }
        let uploads = monthReports.compactMap { $0.avgUpload }
        let avgDown: Double? = downloads.isEmpty ? nil : downloads.reduce(0, +) / Double(downloads.count)
        let avgUp: Double? = uploads.isEmpty ? nil : uploads.reduce(0, +) / Double(uploads.count)

        return MonthlyReport(
            monthStart: startOfLastMonth,
            avgLatency: latencies.reduce(0, +) / Double(latencies.count),
            avgJitter: jitters.reduce(0, +) / Double(jitters.count),
            avgPacketLoss: losses.reduce(0, +) / Double(losses.count),
            avgUptimePercent: uptimes.reduce(0, +) / Double(uptimes.count),
            avgDownload: avgDown,
            avgUpload: avgUp,
            trend: trend
        )
    }
}

// MARK: - Timeline Graph View

class UptimeTimelineGraphView: NSView {
    var events: [ConnectionEvent] = [] {
        didSet { needsDisplay = true }
    }
    var periodDays: Int = 7 {
        didSet { needsDisplay = true }
    }

    private var tooltipView: NSTextField?
    private var cursorLineX: CGFloat?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTracking()
        setupAccessibility()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTracking()
        setupAccessibility()
    }

    private func setupTracking() {
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    private func setupAccessibility() {
        setAccessibilityRole(.image)
        setAccessibilityLabel(NSLocalizedString("reports.timeline.accessibility", comment: ""))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        setupTracking()
    }

    override func mouseExited(with event: NSEvent) {
        cursorLineX = nil
        tooltipView?.removeFromSuperview()
        tooltipView = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let margin: CGFloat = 50
        let graphRect = bounds.insetBy(dx: margin, dy: 30)

        guard graphRect.contains(point) else {
            mouseExited(with: event)
            return
        }

        cursorLineX = point.x
        needsDisplay = true

        // Calculer la date à cette position
        let now = Date()
        let cutoff = now.addingTimeInterval(-Double(periodDays) * 86400)
        let ratio = Double((point.x - graphRect.minX) / graphRect.width)
        let targetDate = cutoff.addingTimeInterval(ratio * Double(periodDays) * 86400)

        // Trouver l'état à cette date
        let isConnected = connectionStateAt(date: targetDate)

        showTooltip(at: point, date: targetDate, connected: isConnected)
    }

    private func connectionStateAt(date: Date) -> Bool {
        let sortedEvents = events.sorted { $0.date > $1.date }
        for event in sortedEvents {
            if event.date <= date {
                return event.connected
            }
        }
        return true // Par défaut connecté
    }

    private func showTooltip(at point: NSPoint, date: Date, connected: Bool) {
        if tooltipView == nil {
            let tooltip = NSTextField(labelWithString: "")
            tooltip.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
            tooltip.isBordered = true
            tooltip.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            addSubview(tooltip)
            tooltipView = tooltip
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM HH:mm"
        let status = connected ? NSLocalizedString("reports.timeline.connected", comment: "") : NSLocalizedString("reports.timeline.disconnected", comment: "")
        tooltipView?.stringValue = " \(formatter.string(from: date)) — \(status) "
        tooltipView?.sizeToFit()

        var tooltipX = point.x + 10
        if tooltipX + tooltipView!.frame.width > bounds.maxX - 10 {
            tooltipX = point.x - tooltipView!.frame.width - 10
        }
        tooltipView?.frame.origin = NSPoint(x: tooltipX, y: point.y + 10)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let margin: CGFloat = 50
        let graphRect = bounds.insetBy(dx: margin, dy: 30)
        guard graphRect.width > 0, graphRect.height > 0 else { return }

        // Fond
        NSColor.windowBackgroundColor.setFill()
        context.fill(bounds)

        // Fond du graphe
        NSColor.controlBackgroundColor.setFill()
        context.fill(graphRect)

        // Calculer les périodes
        let now = Date()
        let cutoff = now.addingTimeInterval(-Double(periodDays) * 86400)
        let totalSeconds = Double(periodDays) * 86400

        // Trier les événements par date
        let sortedEvents = events.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }

        // Dessiner les zones connectées/déconnectées
        let barHeight: CGFloat = 40
        let barY = graphRect.midY - barHeight / 2

        var currentDate = cutoff
        var currentConnected = connectionStateAt(date: cutoff)

        for event in sortedEvents {
            let startX = graphRect.minX + CGFloat((currentDate.timeIntervalSince(cutoff)) / totalSeconds) * graphRect.width
            let endX = graphRect.minX + CGFloat((event.date.timeIntervalSince(cutoff)) / totalSeconds) * graphRect.width

            let rect = CGRect(x: startX, y: barY, width: endX - startX, height: barHeight)

            if currentConnected {
                NSColor.systemGreen.withAlphaComponent(0.7).setFill()
                context.fill(rect)
            } else {
                // Zone déconnectée avec hachures
                NSColor.systemRed.withAlphaComponent(0.3).setFill()
                context.fill(rect)
                drawHatchPattern(in: rect, context: context)
            }

            currentDate = event.date
            currentConnected = event.connected
        }

        // Dernière période jusqu'à maintenant
        let startX = graphRect.minX + CGFloat((currentDate.timeIntervalSince(cutoff)) / totalSeconds) * graphRect.width
        let endX = graphRect.maxX
        let rect = CGRect(x: startX, y: barY, width: endX - startX, height: barHeight)

        if currentConnected {
            NSColor.systemGreen.withAlphaComponent(0.7).setFill()
            context.fill(rect)
        } else {
            NSColor.systemRed.withAlphaComponent(0.3).setFill()
            context.fill(rect)
            drawHatchPattern(in: rect, context: context)
        }

        // Bordure du graphe
        NSColor.separatorColor.setStroke()
        context.stroke(graphRect, width: 1)

        // Labels de dates
        drawDateLabels(in: graphRect, cutoff: cutoff, now: now)

        // Ligne de curseur
        if let cursorX = cursorLineX {
            context.setStrokeColor(NSColor.labelColor.cgColor)
            context.setLineDash(phase: 0, lengths: [4, 4])
            context.setLineWidth(1)
            context.move(to: CGPoint(x: cursorX, y: graphRect.minY))
            context.addLine(to: CGPoint(x: cursorX, y: graphRect.maxY))
            context.strokePath()
        }
    }

    private func drawHatchPattern(in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.clip(to: rect)

        NSColor.systemRed.withAlphaComponent(0.5).setStroke()
        context.setLineWidth(1)

        let spacing: CGFloat = 8
        var x = rect.minX - rect.height
        while x < rect.maxX {
            context.move(to: CGPoint(x: x, y: rect.minY))
            context.addLine(to: CGPoint(x: x + rect.height, y: rect.maxY))
            x += spacing
        }
        context.strokePath()

        context.restoreGState()
    }

    private func drawDateLabels(in rect: CGRect, cutoff: Date, now: Date) {
        let formatter = DateFormatter()
        formatter.dateFormat = periodDays <= 7 ? "EEE" : "dd/MM"

        let labelCount = min(periodDays, 7)
        let step = Double(periodDays) / Double(labelCount)

        for i in 0...labelCount {
            let date = cutoff.addingTimeInterval(Double(i) * step * 86400)
            let x = rect.minX + (CGFloat(i) / CGFloat(labelCount)) * rect.width

            let label = formatter.string(from: date)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: x - size.width / 2, y: rect.minY - 20), withAttributes: attrs)
        }
    }

    /// Calcule les statistiques de la période.
    func calculateStatistics() -> (uptime: Double, disconnections: Int, longestDisconnect: TimeInterval?, longestConnect: TimeInterval?) {
        let now = Date()
        let cutoff = now.addingTimeInterval(-Double(periodDays) * 86400)
        let sortedEvents = events.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }

        var totalUp: TimeInterval = 0
        var totalDown: TimeInterval = 0
        var disconnections = 0
        var longestDisconnect: TimeInterval = 0
        var longestConnect: TimeInterval = 0

        var currentDate = cutoff
        var currentConnected = connectionStateAt(date: cutoff)
        var currentPeriodStart = cutoff

        for event in sortedEvents {
            let duration = event.date.timeIntervalSince(currentDate)

            if currentConnected {
                totalUp += duration
                let connectDuration = event.date.timeIntervalSince(currentPeriodStart)
                if connectDuration > longestConnect {
                    longestConnect = connectDuration
                }
            } else {
                totalDown += duration
                let disconnectDuration = event.date.timeIntervalSince(currentPeriodStart)
                if disconnectDuration > longestDisconnect {
                    longestDisconnect = disconnectDuration
                }
            }

            if !event.connected {
                disconnections += 1
            }

            currentDate = event.date
            currentPeriodStart = event.date
            currentConnected = event.connected
        }

        // Dernière période
        let duration = now.timeIntervalSince(currentDate)
        if currentConnected {
            totalUp += duration
            let connectDuration = now.timeIntervalSince(currentPeriodStart)
            if connectDuration > longestConnect {
                longestConnect = connectDuration
            }
        } else {
            totalDown += duration
            let disconnectDuration = now.timeIntervalSince(currentPeriodStart)
            if disconnectDuration > longestDisconnect {
                longestDisconnect = disconnectDuration
            }
        }

        let totalTime = Double(periodDays) * 86400
        let uptime = (totalUp / totalTime) * 100

        return (uptime, disconnections, longestDisconnect > 0 ? longestDisconnect : nil, longestConnect > 0 ? longestConnect : nil)
    }
}

// MARK: - Profile Comparison Bar Chart

class ProfileComparisonBarChart: NSView {
    var profile1: NetworkProfile? { didSet { needsDisplay = true } }
    var profile2: NetworkProfile? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let margin: CGFloat = 40
        let graphRect = bounds.insetBy(dx: margin, dy: 30)
        guard graphRect.width > 0, graphRect.height > 0 else { return }

        // Fond
        NSColor.controlBackgroundColor.setFill()
        context.fill(graphRect)

        guard let p1 = profile1, let p2 = profile2 else {
            // Message "sélectionnez deux profils"
            let msg = NSLocalizedString("reports.comparison.select_profiles", comment: "")
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let size = msg.size(withAttributes: attrs)
            msg.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
            return
        }

        // Calculer les moyennes
        let p1Latency = p1.performanceSnapshots.compactMap { $0.avgLatency }.reduce(0, +) / max(1, Double(p1.performanceSnapshots.compactMap { $0.avgLatency }.count))
        let p2Latency = p2.performanceSnapshots.compactMap { $0.avgLatency }.reduce(0, +) / max(1, Double(p2.performanceSnapshots.compactMap { $0.avgLatency }.count))
        let p1Download = p1.performanceSnapshots.compactMap { $0.downloadMbps }.reduce(0, +) / max(1, Double(p1.performanceSnapshots.compactMap { $0.downloadMbps }.count))
        let p2Download = p2.performanceSnapshots.compactMap { $0.downloadMbps }.reduce(0, +) / max(1, Double(p2.performanceSnapshots.compactMap { $0.downloadMbps }.count))
        let p1Upload = p1.performanceSnapshots.compactMap { $0.uploadMbps }.reduce(0, +) / max(1, Double(p1.performanceSnapshots.compactMap { $0.uploadMbps }.count))
        let p2Upload = p2.performanceSnapshots.compactMap { $0.uploadMbps }.reduce(0, +) / max(1, Double(p2.performanceSnapshots.compactMap { $0.uploadMbps }.count))

        // Dessiner les barres (3 groupes: latence, download, upload)
        let metrics = [
            (NSLocalizedString("reports.comparison.latency", comment: ""), p1Latency, p2Latency, true),  // true = lower is better
            (NSLocalizedString("reports.comparison.download", comment: ""), p1Download, p2Download, false),
            (NSLocalizedString("reports.comparison.upload", comment: ""), p1Upload, p2Upload, false)
        ]

        let groupWidth = graphRect.width / CGFloat(metrics.count)
        let barWidth: CGFloat = 30
        let gap: CGFloat = 10

        for (index, metric) in metrics.enumerated() {
            let groupX = graphRect.minX + CGFloat(index) * groupWidth + groupWidth / 2

            // Normaliser les valeurs
            let maxVal = max(metric.1, metric.2, 1)
            let scale = (graphRect.height - 40) / CGFloat(maxVal)

            // Barre profil 1
            let h1 = CGFloat(metric.1) * scale
            let bar1Rect = CGRect(x: groupX - barWidth - gap / 2, y: graphRect.minY + 20, width: barWidth, height: h1)
            NSColor.systemBlue.setFill()
            context.fill(bar1Rect)

            // Barre profil 2
            let h2 = CGFloat(metric.2) * scale
            let bar2Rect = CGRect(x: groupX + gap / 2, y: graphRect.minY + 20, width: barWidth, height: h2)
            NSColor.systemOrange.setFill()
            context.fill(bar2Rect)

            // Label métrique
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
            let size = metric.0.size(withAttributes: attrs)
            metric.0.draw(at: NSPoint(x: groupX - size.width / 2, y: graphRect.minY - 5), withAttributes: attrs)

            // Valeurs au-dessus des barres
            let valAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let val1 = String(format: "%.1f", metric.1)
            let val2 = String(format: "%.1f", metric.2)
            val1.draw(at: NSPoint(x: bar1Rect.midX - val1.size(withAttributes: valAttrs).width / 2, y: bar1Rect.maxY + 2), withAttributes: valAttrs)
            val2.draw(at: NSPoint(x: bar2Rect.midX - val2.size(withAttributes: valAttrs).width / 2, y: bar2Rect.maxY + 2), withAttributes: valAttrs)
        }

        // Légende
        let legendY = graphRect.maxY - 20
        let legendAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor
        ]

        // Profil 1
        let legend1Rect = CGRect(x: graphRect.minX + 10, y: legendY, width: 12, height: 12)
        NSColor.systemBlue.setFill()
        context.fill(legend1Rect)
        p1.name.draw(at: NSPoint(x: legend1Rect.maxX + 5, y: legendY - 2), withAttributes: legendAttrs)

        // Profil 2
        let legend2Rect = CGRect(x: graphRect.midX, y: legendY, width: 12, height: 12)
        NSColor.systemOrange.setFill()
        context.fill(legend2Rect)
        p2.name.draw(at: NSPoint(x: legend2Rect.maxX + 5, y: legendY - 2), withAttributes: legendAttrs)
    }
}

// MARK: - Reports Window Controller

class ReportsWindowController: NSWindowController {

    // UI Components
    private var tabView: NSTabView!

    // Timeline tab
    private var timelineGraph: UptimeTimelineGraphView!
    private var periodSegmented: NSSegmentedControl!
    private var statsLabels: [NSTextField] = []

    // Comparison tab
    private var profile1Popup: NSPopUpButton!
    private var profile2Popup: NSPopUpButton!
    private var comparisonChart: ProfileComparisonBarChart!
    private var comparisonLabels: [NSTextField] = []

    // Reports tab
    private var reportTypeSegmented: NSSegmentedControl!
    private var reportPeriodPopup: NSPopUpButton!
    private var reportTextView: NSTextView!

    // Buttons
    private var copyButton: NSButton!
    private var exportButton: NSButton!

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 550),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("reports.title", comment: "")
        window.center()
        window.minSize = NSSize(width: 650, height: 450)
        window.isReleasedWhenClosed = false

        super.init(window: window)

        setupUI()
        loadData()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        // Tab View
        tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tabView)

        // Onglet 1: Timeline
        let timelineTab = NSTabViewItem(identifier: "timeline")
        timelineTab.label = NSLocalizedString("reports.tab.timeline", comment: "")
        timelineTab.view = buildTimelineTab()
        tabView.addTabViewItem(timelineTab)

        // Onglet 2: Comparaison
        let comparisonTab = NSTabViewItem(identifier: "comparison")
        comparisonTab.label = NSLocalizedString("reports.tab.comparison", comment: "")
        comparisonTab.view = buildComparisonTab()
        tabView.addTabViewItem(comparisonTab)

        // Onglet 3: Rapports
        let reportsTab = NSTabViewItem(identifier: "reports")
        reportsTab.label = NSLocalizedString("reports.tab.reports", comment: "")
        reportsTab.view = buildReportsTab()
        tabView.addTabViewItem(reportsTab)

        // Boutons en bas
        let buttonStack = NSStackView()
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 10
        contentView.addSubview(buttonStack)

        copyButton = NSButton(title: NSLocalizedString("reports.button.copy", comment: ""), target: self, action: #selector(copyReport))
        exportButton = NSButton(title: NSLocalizedString("reports.button.export_pdf", comment: ""), target: self, action: #selector(exportPDF))

        buttonStack.addArrangedSubview(NSView()) // Spacer
        buttonStack.addArrangedSubview(copyButton)
        buttonStack.addArrangedSubview(exportButton)

        // Constraints
        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            tabView.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -10),

            buttonStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            buttonStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            buttonStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -15),
            buttonStack.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    // MARK: - Timeline Tab

    private func buildTimelineTab() -> NSView {
        let container = NSView()

        // Contrôle de période
        let periodLabel = NSTextField(labelWithString: NSLocalizedString("reports.timeline.period", comment: ""))
        periodLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(periodLabel)

        periodSegmented = NSSegmentedControl(labels: [
            NSLocalizedString("reports.timeline.7days", comment: ""),
            NSLocalizedString("reports.timeline.30days", comment: "")
        ], trackingMode: .selectOne, target: self, action: #selector(periodChanged))
        periodSegmented.translatesAutoresizingMaskIntoConstraints = false
        periodSegmented.selectedSegment = 0
        container.addSubview(periodSegmented)

        // Graphe timeline
        timelineGraph = UptimeTimelineGraphView()
        timelineGraph.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(timelineGraph)

        // Statistiques
        let statsContainer = NSStackView()
        statsContainer.translatesAutoresizingMaskIntoConstraints = false
        statsContainer.orientation = .vertical
        statsContainer.alignment = .leading
        statsContainer.spacing = 8
        container.addSubview(statsContainer)

        let statTitles = [
            NSLocalizedString("reports.timeline.uptime_avg", comment: ""),
            NSLocalizedString("reports.timeline.disconnections", comment: ""),
            NSLocalizedString("reports.timeline.longest_disconnect", comment: ""),
            NSLocalizedString("reports.timeline.longest_connect", comment: "")
        ]

        for title in statTitles {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 8

            let titleLabel = NSTextField(labelWithString: title)
            titleLabel.font = NSFont.systemFont(ofSize: 12)
            titleLabel.textColor = .secondaryLabelColor

            let valueLabel = NSTextField(labelWithString: "—")
            valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

            row.addArrangedSubview(titleLabel)
            row.addArrangedSubview(valueLabel)
            statsContainer.addArrangedSubview(row)
            statsLabels.append(valueLabel)
        }

        // Constraints
        NSLayoutConstraint.activate([
            periodLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 15),
            periodLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 15),

            periodSegmented.centerYAnchor.constraint(equalTo: periodLabel.centerYAnchor),
            periodSegmented.leadingAnchor.constraint(equalTo: periodLabel.trailingAnchor, constant: 10),

            timelineGraph.topAnchor.constraint(equalTo: periodLabel.bottomAnchor, constant: 15),
            timelineGraph.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            timelineGraph.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            timelineGraph.heightAnchor.constraint(equalToConstant: 150),

            statsContainer.topAnchor.constraint(equalTo: timelineGraph.bottomAnchor, constant: 20),
            statsContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            statsContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20)
        ])

        return container
    }

    // MARK: - Comparison Tab

    private func buildComparisonTab() -> NSView {
        let container = NSView()

        // Sélecteurs de profils
        let selectLabel = NSTextField(labelWithString: NSLocalizedString("reports.comparison.compare", comment: ""))
        selectLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(selectLabel)

        profile1Popup = NSPopUpButton()
        profile1Popup.translatesAutoresizingMaskIntoConstraints = false
        profile1Popup.target = self
        profile1Popup.action = #selector(profileSelectionChanged)
        container.addSubview(profile1Popup)

        let vsLabel = NSTextField(labelWithString: NSLocalizedString("reports.comparison.vs", comment: ""))
        vsLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(vsLabel)

        profile2Popup = NSPopUpButton()
        profile2Popup.translatesAutoresizingMaskIntoConstraints = false
        profile2Popup.target = self
        profile2Popup.action = #selector(profileSelectionChanged)
        container.addSubview(profile2Popup)

        // Cartes de comparaison
        let cardsStack = NSStackView()
        cardsStack.translatesAutoresizingMaskIntoConstraints = false
        cardsStack.orientation = .horizontal
        cardsStack.distribution = .fillEqually
        cardsStack.spacing = 20
        container.addSubview(cardsStack)

        // Carte profil 1
        let card1 = createProfileCard(index: 0)
        cardsStack.addArrangedSubview(card1)

        // Carte différence
        let diffCard = createDiffCard()
        cardsStack.addArrangedSubview(diffCard)

        // Carte profil 2
        let card2 = createProfileCard(index: 1)
        cardsStack.addArrangedSubview(card2)

        // Graphe de comparaison
        comparisonChart = ProfileComparisonBarChart()
        comparisonChart.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(comparisonChart)

        // Constraints
        NSLayoutConstraint.activate([
            selectLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 15),
            selectLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 15),

            profile1Popup.centerYAnchor.constraint(equalTo: selectLabel.centerYAnchor),
            profile1Popup.leadingAnchor.constraint(equalTo: selectLabel.trailingAnchor, constant: 10),
            profile1Popup.widthAnchor.constraint(equalToConstant: 150),

            vsLabel.centerYAnchor.constraint(equalTo: selectLabel.centerYAnchor),
            vsLabel.leadingAnchor.constraint(equalTo: profile1Popup.trailingAnchor, constant: 10),

            profile2Popup.centerYAnchor.constraint(equalTo: selectLabel.centerYAnchor),
            profile2Popup.leadingAnchor.constraint(equalTo: vsLabel.trailingAnchor, constant: 10),
            profile2Popup.widthAnchor.constraint(equalToConstant: 150),

            cardsStack.topAnchor.constraint(equalTo: selectLabel.bottomAnchor, constant: 20),
            cardsStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 15),
            cardsStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -15),
            cardsStack.heightAnchor.constraint(equalToConstant: 120),

            comparisonChart.topAnchor.constraint(equalTo: cardsStack.bottomAnchor, constant: 20),
            comparisonChart.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            comparisonChart.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            comparisonChart.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])

        return container
    }

    private func createProfileCard(index: Int) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.cornerRadius = 8

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        card.addSubview(stack)

        let nameLabel = NSTextField(labelWithString: "—")
        nameLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        stack.addArrangedSubview(nameLabel)

        let metrics = ["Latence: —", "Download: —", "Upload: —", "Tests: —"]
        for metric in metrics {
            let label = NSTextField(labelWithString: metric)
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .secondaryLabelColor
            stack.addArrangedSubview(label)
            comparisonLabels.append(label)
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -12)
        ])

        return card
    }

    private func createDiffCard() -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        card.layer?.cornerRadius = 8

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        card.addSubview(stack)

        let titleLabel = NSTextField(labelWithString: NSLocalizedString("reports.comparison.diff", comment: ""))
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(titleLabel)

        for _ in 0..<3 {
            let label = NSTextField(labelWithString: "—")
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            stack.addArrangedSubview(label)
            comparisonLabels.append(label)
        }

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])

        return card
    }

    // MARK: - Reports Tab

    private func buildReportsTab() -> NSView {
        let container = NSView()

        // Type de rapport
        let typeLabel = NSTextField(labelWithString: NSLocalizedString("reports.summary.type", comment: ""))
        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(typeLabel)

        reportTypeSegmented = NSSegmentedControl(labels: [
            NSLocalizedString("reports.summary.weekly", comment: ""),
            NSLocalizedString("reports.summary.monthly", comment: "")
        ], trackingMode: .selectOne, target: self, action: #selector(reportTypeChanged))
        reportTypeSegmented.translatesAutoresizingMaskIntoConstraints = false
        reportTypeSegmented.selectedSegment = 0
        container.addSubview(reportTypeSegmented)

        // Sélecteur de période
        let periodLabel = NSTextField(labelWithString: NSLocalizedString("reports.summary.period", comment: ""))
        periodLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(periodLabel)

        reportPeriodPopup = NSPopUpButton()
        reportPeriodPopup.translatesAutoresizingMaskIntoConstraints = false
        reportPeriodPopup.target = self
        reportPeriodPopup.action = #selector(reportPeriodChanged)
        container.addSubview(reportPeriodPopup)

        // Zone de texte du rapport
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        container.addSubview(scrollView)

        reportTextView = NSTextView()
        reportTextView.isEditable = false
        reportTextView.isSelectable = true
        reportTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        reportTextView.textContainerInset = NSSize(width: 10, height: 10)
        scrollView.documentView = reportTextView

        // Constraints
        NSLayoutConstraint.activate([
            typeLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 15),
            typeLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 15),

            reportTypeSegmented.centerYAnchor.constraint(equalTo: typeLabel.centerYAnchor),
            reportTypeSegmented.leadingAnchor.constraint(equalTo: typeLabel.trailingAnchor, constant: 10),

            periodLabel.centerYAnchor.constraint(equalTo: typeLabel.centerYAnchor),
            periodLabel.leadingAnchor.constraint(equalTo: reportTypeSegmented.trailingAnchor, constant: 20),

            reportPeriodPopup.centerYAnchor.constraint(equalTo: typeLabel.centerYAnchor),
            reportPeriodPopup.leadingAnchor.constraint(equalTo: periodLabel.trailingAnchor, constant: 10),
            reportPeriodPopup.widthAnchor.constraint(equalToConstant: 180),

            scrollView.topAnchor.constraint(equalTo: typeLabel.bottomAnchor, constant: 15),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])

        return container
    }

    // MARK: - Data Loading

    private func loadData() {
        loadTimelineData()
        loadProfilesData()
        loadReportsData()
    }

    private func loadTimelineData() {
        timelineGraph.events = UptimeTracker.loadEvents()
        timelineGraph.periodDays = periodSegmented.selectedSegment == 0 ? 7 : 30
        updateTimelineStats()
    }

    private func updateTimelineStats() {
        let stats = timelineGraph.calculateStatistics()

        statsLabels[0].stringValue = String(format: "%.1f%%", stats.uptime)
        statsLabels[1].stringValue = "\(stats.disconnections)"

        if let longestDisconnect = stats.longestDisconnect {
            statsLabels[2].stringValue = formatDuration(longestDisconnect)
        } else {
            statsLabels[2].stringValue = "—"
        }

        if let longestConnect = stats.longestConnect {
            statsLabels[3].stringValue = formatDuration(longestConnect)
        } else {
            statsLabels[3].stringValue = "—"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if days > 0 {
            return String(format: NSLocalizedString("reports.duration.days_hours", comment: ""), days, hours)
        } else if hours > 0 {
            return String(format: NSLocalizedString("reports.duration.hours_minutes", comment: ""), hours, minutes)
        } else {
            return String(format: NSLocalizedString("reports.duration.minutes", comment: ""), minutes)
        }
    }

    private func loadProfilesData() {
        let profiles = NetworkProfileStorage.load()

        profile1Popup.removeAllItems()
        profile2Popup.removeAllItems()

        if profiles.isEmpty {
            profile1Popup.addItem(withTitle: NSLocalizedString("reports.comparison.no_profiles", comment: ""))
            profile2Popup.addItem(withTitle: NSLocalizedString("reports.comparison.no_profiles", comment: ""))
        } else {
            for profile in profiles {
                profile1Popup.addItem(withTitle: profile.name)
                profile2Popup.addItem(withTitle: profile.name)
            }
            if profiles.count >= 2 {
                profile2Popup.selectItem(at: 1)
            }
        }

        profileSelectionChanged(nil)
    }

    private func loadReportsData() {
        updateReportPeriodPopup()
        updateReportDisplay()
    }

    private func updateReportPeriodPopup() {
        reportPeriodPopup.removeAllItems()

        let formatter = DateFormatter()

        if reportTypeSegmented.selectedSegment == 0 {
            // Hebdomadaire
            let reports = ScheduledTestStorage.loadWeeklyReports()
            formatter.dateFormat = "'Sem.' w/yyyy"

            if reports.isEmpty {
                reportPeriodPopup.addItem(withTitle: NSLocalizedString("reports.summary.no_data", comment: ""))
            } else {
                for report in reports.reversed() {
                    reportPeriodPopup.addItem(withTitle: formatter.string(from: report.weekStart))
                }
            }
        } else {
            // Mensuel
            let reports = ScheduledTestStorage.loadMonthlyReports()
            formatter.dateFormat = "MMMM yyyy"

            if reports.isEmpty {
                reportPeriodPopup.addItem(withTitle: NSLocalizedString("reports.summary.no_data", comment: ""))
            } else {
                for report in reports.reversed() {
                    reportPeriodPopup.addItem(withTitle: formatter.string(from: report.monthStart))
                }
            }
        }
    }

    private func updateReportDisplay() {
        var text = ""

        if reportTypeSegmented.selectedSegment == 0 {
            let reports = ScheduledTestStorage.loadWeeklyReports()
            let index = reports.count - 1 - reportPeriodPopup.indexOfSelectedItem

            if index >= 0 && index < reports.count {
                let report = reports[index]
                text = formatWeeklyReport(report)
            } else {
                text = NSLocalizedString("reports.summary.no_data_detail", comment: "")
            }
        } else {
            let reports = ScheduledTestStorage.loadMonthlyReports()
            let index = reports.count - 1 - reportPeriodPopup.indexOfSelectedItem

            if index >= 0 && index < reports.count {
                let report = reports[index]
                text = formatMonthlyReport(report)
            } else {
                text = NSLocalizedString("reports.summary.no_data_detail", comment: "")
            }
        }

        reportTextView.string = text
    }

    private func formatWeeklyReport(_ report: WeeklyReport) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"

        let endDate = Calendar.current.date(byAdding: .day, value: 6, to: report.weekStart)!

        var text = """
        ╔══════════════════════════════════════════════════════════════╗
        ║  RAPPORT HEBDOMADAIRE                                        ║
        ║  \(dateFormatter.string(from: report.weekStart)) — \(dateFormatter.string(from: endDate))                              ║
        ╚══════════════════════════════════════════════════════════════╝

        ┌─────────────────────────────────────────────────────────────┐
        │  RÉSUMÉ                                                      │
        ├─────────────────────────────────────────────────────────────┤
        │  Tests effectués       : \(String(format: "%6d", report.totalTestCount))                            │
        │  Dégradations          : \(String(format: "%6d", report.degradationCount))                            │
        │  Uptime                : \(String(format: "%5.1f%%", report.avgUptimePercent))                           │
        └─────────────────────────────────────────────────────────────┘

        ┌─────────────────────────────────────────────────────────────┐
        │  QUALITÉ RÉSEAU                                              │
        ├─────────────────────────────────────────────────────────────┤
        │  Latence moyenne       : \(String(format: "%5.1f ms", report.avgLatency))                          │
        │  Jitter moyen          : \(String(format: "%5.1f ms", report.avgJitter))                          │
        │  Perte moyenne         : \(String(format: "%5.2f%%", report.avgPacketLoss))                           │
        └─────────────────────────────────────────────────────────────┘

        """

        if let down = report.avgDownload, let up = report.avgUpload {
            text += """
            ┌─────────────────────────────────────────────────────────────┐
            │  DÉBIT                                                       │
            ├─────────────────────────────────────────────────────────────┤
            │  Download moyen       : \(String(format: "%5.1f Mbps", down))                        │
            │  Upload moyen         : \(String(format: "%5.1f Mbps", up))                        │
            └─────────────────────────────────────────────────────────────┘

            """
        }

        text += """
        ┌─────────────────────────────────────────────────────────────┐
        │  TENDANCE : \(report.trend.symbol) \(report.trend.label.padding(toLength: 45, withPad: " ", startingAt: 0))│
        └─────────────────────────────────────────────────────────────┘
        """

        return text
    }

    private func formatMonthlyReport(_ report: MonthlyReport) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM yyyy"

        var text = """
        ╔══════════════════════════════════════════════════════════════╗
        ║  RAPPORT MENSUEL                                             ║
        ║  \(dateFormatter.string(from: report.monthStart).padding(toLength: 52, withPad: " ", startingAt: 0))║
        ╚══════════════════════════════════════════════════════════════╝

        ┌─────────────────────────────────────────────────────────────┐
        │  RÉSUMÉ                                                      │
        ├─────────────────────────────────────────────────────────────┤
        │  Uptime moyen          : \(String(format: "%5.1f%%", report.avgUptimePercent))                           │
        └─────────────────────────────────────────────────────────────┘

        ┌─────────────────────────────────────────────────────────────┐
        │  QUALITÉ RÉSEAU MOYENNE                                      │
        ├─────────────────────────────────────────────────────────────┤
        │  Latence               : \(String(format: "%5.1f ms", report.avgLatency))                          │
        │  Jitter                : \(String(format: "%5.1f ms", report.avgJitter))                          │
        │  Perte de paquets      : \(String(format: "%5.2f%%", report.avgPacketLoss))                           │
        └─────────────────────────────────────────────────────────────┘

        """

        if let down = report.avgDownload, let up = report.avgUpload {
            text += """
            ┌─────────────────────────────────────────────────────────────┐
            │  DÉBIT MOYEN                                                 │
            ├─────────────────────────────────────────────────────────────┤
            │  Download             : \(String(format: "%5.1f Mbps", down))                        │
            │  Upload               : \(String(format: "%5.1f Mbps", up))                        │
            └─────────────────────────────────────────────────────────────┘

            """
        }

        text += """
        ┌─────────────────────────────────────────────────────────────┐
        │  TENDANCE : \(report.trend.symbol) \(report.trend.label.padding(toLength: 45, withPad: " ", startingAt: 0))│
        └─────────────────────────────────────────────────────────────┘
        """

        return text
    }

    // MARK: - Actions

    @objc private func periodChanged(_ sender: NSSegmentedControl) {
        timelineGraph.periodDays = sender.selectedSegment == 0 ? 7 : 30
        updateTimelineStats()
    }

    @objc private func profileSelectionChanged(_ sender: Any?) {
        let profiles = NetworkProfileStorage.load()

        if profiles.count >= 2 {
            let idx1 = profile1Popup.indexOfSelectedItem
            let idx2 = profile2Popup.indexOfSelectedItem

            if idx1 < profiles.count && idx2 < profiles.count {
                comparisonChart.profile1 = profiles[idx1]
                comparisonChart.profile2 = profiles[idx2]
                updateComparisonLabels(profiles[idx1], profiles[idx2])
            }
        }
    }

    private func updateComparisonLabels(_ p1: NetworkProfile, _ p2: NetworkProfile) {
        // Les labels de comparaison seront mis à jour ici
        // Simplification pour l'instant
    }

    @objc private func reportTypeChanged(_ sender: NSSegmentedControl) {
        updateReportPeriodPopup()
        updateReportDisplay()
    }

    @objc private func reportPeriodChanged(_ sender: NSPopUpButton) {
        updateReportDisplay()
    }

    @objc private func copyReport() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch tabView.selectedTabViewItem?.identifier as? String {
        case "timeline":
            let stats = timelineGraph.calculateStatistics()
            let text = """
            Timeline de connexion (\(timelineGraph.periodDays) jours)
            Uptime: \(String(format: "%.1f%%", stats.uptime))
            Déconnexions: \(stats.disconnections)
            """
            pasteboard.setString(text, forType: .string)
        case "reports":
            pasteboard.setString(reportTextView.string, forType: .string)
        default:
            break
        }
    }

    @objc private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "NetDisco_Report_\(Date().formatted(.iso8601)).pdf"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Génération PDF simplifiée
        let text = reportTextView.string
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        ]
        let attrString = NSAttributedString(string: text, attributes: attrs)

        let printInfo = NSPrintInfo.shared
        printInfo.paperSize = NSSize(width: 595, height: 842) // A4
        printInfo.topMargin = 50
        printInfo.bottomMargin = 50
        printInfo.leftMargin = 50
        printInfo.rightMargin = 50

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 495, height: 742))
        textView.textStorage?.setAttributedString(attrString)

        let printOp = NSPrintOperation(view: textView)
        printOp.printInfo = printInfo
        printOp.printInfo.jobDisposition = .save
        printOp.printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        printOp.showsPrintPanel = false
        printOp.showsProgressPanel = false
        printOp.run()
    }
}

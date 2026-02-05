// DashboardWindowController.swift
// NetDisco
//
// Dashboard de monitoring continu. Vue d'ensemble temps réel de l'état réseau
// avec refresh automatique configurable.

import Cocoa
import Network
import CoreWLAN
import SystemConfiguration

// MARK: - Dashboard Panel

class DashboardPanel: NSView {
    let titleLabel: NSTextField
    let valueLabel: NSTextField
    let subtitleLabel: NSTextField
    private let iconView: NSImageView

    var onRefresh: (() -> Void)?

    init(title: String, icon: String) {
        titleLabel = NSTextField(labelWithString: title)
        valueLabel = NSTextField(labelWithString: "—")
        subtitleLabel = NSTextField(labelWithString: "")
        iconView = NSImageView()

        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1

        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = NSFont.systemFont(ofSize: 10)
        subtitleLabel.textColor = .tertiaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: title) {
            iconView.image = img
            iconView.contentTintColor = .controlAccentColor
        }
        iconView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(valueLabel)
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),

            valueLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            subtitleLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    func refresh() {
        onRefresh?()
    }
}

// MARK: - DashboardWindowController

class DashboardWindowController: NSWindowController {

    // Panels
    private var connectionPanel: DashboardPanel!
    private var latencyPanel: DashboardPanel!
    private var throughputPanel: DashboardPanel!
    private var wifiPanel: DashboardPanel!
    private var ipPanel: DashboardPanel!
    private var qualityPanel: DashboardPanel!

    private var alertsLabel: NSTextField!
    private var refreshPopup: NSPopUpButton!

    private var refreshTimer: Timer?
    private var monitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "DashboardMonitor")

    // State
    private var currentLatency: Double = 0
    private var currentJitter: Double = 0
    private var lastPingTime: Date?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("dashboard.title", comment: "")
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 550, height: 400)
        self.init(window: window)
        setupUI()
        setupMonitor()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Header
        let headerStack = NSStackView()
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(headerStack)

        let titleLabel = NSTextField(labelWithString: NSLocalizedString("dashboard.title", comment: ""))
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        headerStack.addArrangedSubview(titleLabel)

        headerStack.addArrangedSubview(NSView())  // Spacer

        let refreshLabel = NSTextField(labelWithString: NSLocalizedString("dashboard.refresh", comment: "") + " :")
        refreshLabel.font = NSFont.systemFont(ofSize: 11)
        headerStack.addArrangedSubview(refreshLabel)

        refreshPopup = NSPopUpButton()
        refreshPopup.addItems(withTitles: ["5s", "10s", "30s", "60s"])
        refreshPopup.selectItem(at: 1)  // Default 10s
        refreshPopup.target = self
        refreshPopup.action = #selector(refreshIntervalChanged)
        headerStack.addArrangedSubview(refreshPopup)

        // Grid de panels (2x3)
        let gridStack = NSStackView()
        gridStack.orientation = .vertical
        gridStack.spacing = 12
        gridStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(gridStack)

        // Row 1
        let row1 = NSStackView()
        row1.orientation = .horizontal
        row1.spacing = 12
        row1.distribution = .fillEqually

        connectionPanel = DashboardPanel(title: NSLocalizedString("dashboard.connection", comment: ""), icon: "network")
        latencyPanel = DashboardPanel(title: NSLocalizedString("dashboard.latency", comment: ""), icon: "timer")
        throughputPanel = DashboardPanel(title: NSLocalizedString("dashboard.throughput", comment: ""), icon: "arrow.up.arrow.down")

        row1.addArrangedSubview(connectionPanel)
        row1.addArrangedSubview(latencyPanel)
        row1.addArrangedSubview(throughputPanel)
        gridStack.addArrangedSubview(row1)

        // Row 2
        let row2 = NSStackView()
        row2.orientation = .horizontal
        row2.spacing = 12
        row2.distribution = .fillEqually

        wifiPanel = DashboardPanel(title: NSLocalizedString("dashboard.wifi", comment: ""), icon: "wifi")
        ipPanel = DashboardPanel(title: NSLocalizedString("dashboard.public_ip", comment: ""), icon: "globe")
        qualityPanel = DashboardPanel(title: NSLocalizedString("dashboard.quality_24h", comment: ""), icon: "chart.bar.fill")

        row2.addArrangedSubview(wifiPanel)
        row2.addArrangedSubview(ipPanel)
        row2.addArrangedSubview(qualityPanel)
        gridStack.addArrangedSubview(row2)

        // Alerts section
        let alertsBox = NSBox()
        alertsBox.title = NSLocalizedString("dashboard.alerts", comment: "")
        alertsBox.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(alertsBox)

        alertsLabel = NSTextField(wrappingLabelWithString: "")
        alertsLabel.font = NSFont.systemFont(ofSize: 12)
        alertsLabel.translatesAutoresizingMaskIntoConstraints = false
        alertsBox.contentView?.addSubview(alertsLabel)

        if let cv = alertsBox.contentView {
            NSLayoutConstraint.activate([
                alertsLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: 8),
                alertsLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 8),
                alertsLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -8),
                alertsLabel.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -8),
            ])
        }

        // Quick actions
        let actionsStack = NSStackView()
        actionsStack.orientation = .horizontal
        actionsStack.spacing = 12
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(actionsStack)

        let speedTestButton = NSButton(title: NSLocalizedString("dashboard.action.speedtest", comment: ""), target: self, action: #selector(openSpeedTest))
        speedTestButton.bezelStyle = .rounded
        actionsStack.addArrangedSubview(speedTestButton)

        let tracerouteButton = NSButton(title: NSLocalizedString("dashboard.action.traceroute", comment: ""), target: self, action: #selector(openTraceroute))
        tracerouteButton.bezelStyle = .rounded
        actionsStack.addArrangedSubview(tracerouteButton)

        let detailsButton = NSButton(title: NSLocalizedString("dashboard.action.details", comment: ""), target: self, action: #selector(openDetails))
        detailsButton.bezelStyle = .rounded
        actionsStack.addArrangedSubview(detailsButton)

        // Panel height constraints
        for panel in [connectionPanel, latencyPanel, throughputPanel, wifiPanel, ipPanel, qualityPanel] {
            panel?.heightAnchor.constraint(equalToConstant: 100).isActive = true
        }

        // Layout
        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            headerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            gridStack.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 16),
            gridStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            gridStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            alertsBox.topAnchor.constraint(equalTo: gridStack.bottomAnchor, constant: 16),
            alertsBox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            alertsBox.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            alertsBox.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),

            actionsStack.topAnchor.constraint(equalTo: alertsBox.bottomAnchor, constant: 16),
            actionsStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            actionsStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])

        // Setup panel refresh handlers
        setupPanelHandlers()
    }

    private func setupPanelHandlers() {
        connectionPanel.onRefresh = { [weak self] in self?.refreshConnectionPanel() }
        latencyPanel.onRefresh = { [weak self] in self?.refreshLatencyPanel() }
        throughputPanel.onRefresh = { [weak self] in self?.refreshThroughputPanel() }
        wifiPanel.onRefresh = { [weak self] in self?.refreshWiFiPanel() }
        ipPanel.onRefresh = { [weak self] in self?.refreshIPPanel() }
        qualityPanel.onRefresh = { [weak self] in self?.refreshQualityPanel() }
    }

    private func setupMonitor() {
        monitor = NWPathMonitor()
        monitor?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.updateConnectionStatus(path)
            }
        }
        monitor?.start(queue: monitorQueue)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        startRefresh()
        refreshAll()
    }

    private func startRefresh() {
        let intervals: [TimeInterval] = [5, 10, 30, 60]
        let interval = intervals[refreshPopup.indexOfSelectedItem]

        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshAll()
        }
    }

    @objc private func refreshIntervalChanged() {
        startRefresh()
    }

    private func refreshAll() {
        connectionPanel.refresh()
        latencyPanel.refresh()
        throughputPanel.refresh()
        wifiPanel.refresh()
        ipPanel.refresh()
        qualityPanel.refresh()
        refreshAlerts()
    }

    // MARK: - Panel Refresh Methods

    private func updateConnectionStatus(_ path: NWPath) {
        if path.status == .satisfied {
            connectionPanel.valueLabel.stringValue = "● " + NSLocalizedString("dashboard.connected", comment: "")
            connectionPanel.valueLabel.textColor = .systemGreen

            var subtitle = ""
            if path.usesInterfaceType(.wifi) {
                subtitle = "WiFi"
                if let ssid = CWWiFiClient.shared().interface()?.ssid() {
                    subtitle += ": \(ssid)"
                }
            } else if path.usesInterfaceType(.wiredEthernet) {
                subtitle = "Ethernet"
            } else if path.usesInterfaceType(.cellular) {
                subtitle = "Cellular"
            }
            connectionPanel.subtitleLabel.stringValue = subtitle
        } else {
            connectionPanel.valueLabel.stringValue = "○ " + NSLocalizedString("dashboard.disconnected", comment: "")
            connectionPanel.valueLabel.textColor = .systemRed
            connectionPanel.subtitleLabel.stringValue = ""
        }
    }

    private func refreshConnectionPanel() {
        // Déclenché par le monitor
    }

    private func refreshLatencyPanel() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let latency = self?.pingHost("8.8.8.8")

            DispatchQueue.main.async {
                if let lat = latency {
                    self?.currentLatency = lat
                    self?.latencyPanel.valueLabel.stringValue = String(format: "%.0f ms", lat)

                    // Color based on latency
                    if lat < 50 {
                        self?.latencyPanel.valueLabel.textColor = .systemGreen
                    } else if lat < 100 {
                        self?.latencyPanel.valueLabel.textColor = .systemOrange
                    } else {
                        self?.latencyPanel.valueLabel.textColor = .systemRed
                    }

                    self?.latencyPanel.subtitleLabel.stringValue = String(format: "Jitter: %.1f ms", self?.currentJitter ?? 0)
                } else {
                    self?.latencyPanel.valueLabel.stringValue = "—"
                    self?.latencyPanel.valueLabel.textColor = .tertiaryLabelColor
                    self?.latencyPanel.subtitleLabel.stringValue = NSLocalizedString("dashboard.timeout", comment: "")
                }
            }
        }
    }

    private func refreshThroughputPanel() {
        // Lire les compteurs réseau
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            throughputPanel.valueLabel.stringValue = "—"
            return
        }
        defer { freeifaddrs(ifaddr) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first

        while let addr = cursor {
            defer { cursor = addr.pointee.ifa_next }
            guard let sa = addr.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: addr.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("utun") else { continue }

            if let data = addr.pointee.ifa_data {
                let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                totalIn += UInt64(networkData.ifi_ibytes)
                totalOut += UInt64(networkData.ifi_obytes)
            }
        }

        // Afficher le total de session (pas le rate instantané)
        let inStr = formatBytes(totalIn)
        let outStr = formatBytes(totalOut)
        throughputPanel.valueLabel.stringValue = "↓ \(inStr)"
        throughputPanel.subtitleLabel.stringValue = "↑ \(outStr)"
    }

    private func refreshWiFiPanel() {
        guard let interface = CWWiFiClient.shared().interface() else {
            wifiPanel.valueLabel.stringValue = "—"
            wifiPanel.subtitleLabel.stringValue = NSLocalizedString("dashboard.no_wifi", comment: "")
            return
        }

        let rssi = interface.rssiValue()
        wifiPanel.valueLabel.stringValue = "\(rssi) dBm"

        if rssi >= -50 {
            wifiPanel.valueLabel.textColor = .systemGreen
        } else if rssi >= -70 {
            wifiPanel.valueLabel.textColor = .systemOrange
        } else {
            wifiPanel.valueLabel.textColor = .systemRed
        }

        if let channel = interface.wlanChannel() {
            wifiPanel.subtitleLabel.stringValue = "Canal \(channel.channelNumber)"
        }
    }

    private func refreshIPPanel() {
        ipPanel.valueLabel.stringValue = "..."
        ipPanel.subtitleLabel.stringValue = ""

        guard let url = URL(string: "https://api.ipify.org") else { return }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                if let data = data, let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    self?.ipPanel.valueLabel.stringValue = ip

                    // Comparer avec l'IP connue
                    let lastIP = IPChangeMonitor.shared.lastKnownIP
                    if let last = lastIP, last != ip {
                        self?.ipPanel.subtitleLabel.stringValue = NSLocalizedString("dashboard.ip_changed", comment: "")
                        self?.ipPanel.subtitleLabel.textColor = .systemOrange
                    } else {
                        self?.ipPanel.subtitleLabel.stringValue = ""
                    }
                } else {
                    self?.ipPanel.valueLabel.stringValue = "—"
                    self?.ipPanel.subtitleLabel.stringValue = error?.localizedDescription ?? ""
                }
            }
        }.resume()
    }

    private func refreshQualityPanel() {
        // Charger les données de qualité des dernières 24h
        // (réutiliser QualityHistoryStorage si disponible)
        qualityPanel.valueLabel.stringValue = "—"
        qualityPanel.subtitleLabel.stringValue = NSLocalizedString("dashboard.quality_no_data", comment: "")

        // Placeholder - l'intégration réelle dépend de QualityHistoryStorage
    }

    private func refreshAlerts() {
        var state = NetworkState()
        state.isConnected = monitor?.currentPath.status == .satisfied
        state.latencyMs = currentLatency
        state.jitterMs = currentJitter

        if let rssi = CWWiFiClient.shared().interface()?.rssiValue() {
            state.rssiDbm = rssi
            state.interfaceType = .wifi
        }

        let alerts = AutoAnalyzer.shared.analyze(state)

        if alerts.isEmpty {
            alertsLabel.stringValue = "✓ " + NSLocalizedString("dashboard.no_alerts", comment: "")
            alertsLabel.textColor = .systemGreen
        } else {
            var text = ""
            for alert in alerts.prefix(3) {
                text += "\(alert.severity.icon) \(alert.title)\n"
            }
            if alerts.count > 3 {
                text += String(format: NSLocalizedString("dashboard.more_alerts", comment: ""), alerts.count - 3)
            }
            alertsLabel.stringValue = text.trimmingCharacters(in: .newlines)
            alertsLabel.textColor = alerts.first?.severity == .critical ? .systemRed : .systemOrange
        }
    }

    // MARK: - Helpers

    private func pingHost(_ host: String) -> Double? {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard sock >= 0 else { return nil }
        defer { Darwin.close(sock) }

        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var infoPtr: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &infoPtr) == 0, let info = infoPtr else { return nil }
        defer { freeaddrinfo(infoPtr) }

        var packet = [UInt8](repeating: 0, count: 64)
        packet[0] = 8
        let pid = UInt16(getpid() & 0xFFFF)
        packet[4] = UInt8(pid >> 8)
        packet[5] = UInt8(pid & 0xFF)

        var sum: UInt32 = 0
        for i in stride(from: 0, to: packet.count, by: 2) {
            sum += UInt32(packet[i]) << 8 | UInt32(packet[i+1])
        }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        let checksum = ~UInt16(sum)
        packet[2] = UInt8(checksum >> 8)
        packet[3] = UInt8(checksum & 0xFF)

        let startTime = CFAbsoluteTimeGetCurrent()
        let sent = packet.withUnsafeBytes { buf in
            sendto(sock, buf.baseAddress, buf.count, 0, info.pointee.ai_addr, socklen_t(info.pointee.ai_addrlen))
        }
        guard sent == packet.count else { return nil }

        var recvBuf = [UInt8](repeating: 0, count: 1024)
        var srcAddr = sockaddr_in()
        var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        let recvLen = withUnsafeMutablePointer(to: &srcAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                recvfrom(sock, &recvBuf, recvBuf.count, 0, sa, &srcLen)
            }
        }

        guard recvLen > 0 else { return nil }

        let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        // Calculate jitter
        if let lastTime = lastPingTime {
            let timeDiff = Date().timeIntervalSince(lastTime)
            if timeDiff < 15 {  // Only if recent
                currentJitter = abs(latency - currentLatency) * 0.1 + currentJitter * 0.9  // EMA
            }
        }
        lastPingTime = Date()

        return latency
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let b = Double(bytes)
        if b < 1024 { return String(format: "%.0f o", b) }
        if b < 1024 * 1024 { return String(format: "%.1f Ko", b / 1024) }
        if b < 1024 * 1024 * 1024 { return String(format: "%.1f Mo", b / (1024 * 1024)) }
        return String(format: "%.2f Go", b / (1024 * 1024 * 1024))
    }

    // MARK: - Actions

    @objc private func openSpeedTest() {
        (NSApp.delegate as? AppDelegate)?.performShowSpeedTest()
    }

    @objc private func openTraceroute() {
        (NSApp.delegate as? AppDelegate)?.performShowTraceroute()
    }

    @objc private func openDetails() {
        (NSApp.delegate as? AppDelegate)?.performShowDetails()
    }

    // MARK: - Cleanup

    override func close() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        monitor?.cancel()
        monitor = nil
        super.close()
    }
}

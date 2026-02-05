// MTRWindowController.swift
// NetDisco
//
// MTR (My Traceroute) - Combine traceroute avec ping continu.
// Affiche des statistiques en temps réel pour chaque hop.

import Cocoa
import Darwin

// MARK: - MTR Hop

class MTRHop {
    let hopNumber: Int
    var ipAddress: String
    var hostname: String?
    var latencies: [Double] = []
    var sentCount: Int = 0
    var timeoutCount: Int = 0

    init(hopNumber: Int, ipAddress: String) {
        self.hopNumber = hopNumber
        self.ipAddress = ipAddress
    }

    var receivedCount: Int {
        return sentCount - timeoutCount
    }

    var avgLatency: Double {
        guard !latencies.isEmpty else { return 0 }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    var minLatency: Double {
        latencies.min() ?? 0
    }

    var maxLatency: Double {
        latencies.max() ?? 0
    }

    var jitter: Double {
        guard latencies.count > 1 else { return 0 }
        var diffs: [Double] = []
        for i in 1..<latencies.count {
            diffs.append(abs(latencies[i] - latencies[i-1]))
        }
        return diffs.reduce(0, +) / Double(diffs.count)
    }

    var lossPercent: Double {
        guard sentCount > 0 else { return 0 }
        return Double(timeoutCount) / Double(sentCount) * 100
    }
}

// MARK: - MTRWindowController

class MTRWindowController: NSWindowController {

    private var targetField: NSTextField!
    private var startButton: NSButton!
    private var stopButton: NSButton!
    private var progressIndicator: NSProgressIndicator!
    private var statusLabel: NSTextField!
    private var tableView: NSTableView!

    private var hops: [MTRHop] = []
    private var pingTimer: Timer?
    private var isRunning = false
    private var targetHost: String = ""

    private let maxTTL = 30
    private let maxLatencies = 100  // Garder les 100 dernières mesures

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("mtr.title", comment: "")
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 650, height: 400)
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Target input
        let targetLabel = NSTextField(labelWithString: NSLocalizedString("mtr.target", comment: "") + " :")
        targetLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        targetLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(targetLabel)

        targetField = NSTextField()
        targetField.placeholderString = "8.8.8.8"
        targetField.translatesAutoresizingMaskIntoConstraints = false
        targetField.target = self
        targetField.action = #selector(startMTR)
        contentView.addSubview(targetField)

        startButton = NSButton(title: NSLocalizedString("mtr.start", comment: ""), target: self, action: #selector(startMTR))
        startButton.bezelStyle = .rounded
        startButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(startButton)

        stopButton = NSButton(title: NSLocalizedString("mtr.stop", comment: ""), target: self, action: #selector(stopMTR))
        stopButton.bezelStyle = .rounded
        stopButton.isEnabled = false
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stopButton)

        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.isHidden = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(progressIndicator)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusLabel)

        // Table
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)

        tableView = NSTableView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 24
        tableView.usesAlternatingRowBackgroundColors = true

        let cols: [(String, String, CGFloat)] = [
            ("hop", "#", 35),
            ("ip", "IP", 120),
            ("hostname", NSLocalizedString("mtr.col.hostname", comment: ""), 150),
            ("sent", NSLocalizedString("mtr.col.sent", comment: ""), 50),
            ("loss", NSLocalizedString("mtr.col.loss", comment: ""), 55),
            ("avg", NSLocalizedString("mtr.col.avg", comment: ""), 65),
            ("min", NSLocalizedString("mtr.col.min", comment: ""), 60),
            ("max", NSLocalizedString("mtr.col.max", comment: ""), 60),
            ("jitter", NSLocalizedString("mtr.col.jitter", comment: ""), 60)
        ]

        for (id, title, width) in cols {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            tableView.addTableColumn(col)
        }

        scrollView.documentView = tableView

        // Buttons
        let copyButton = NSButton(title: NSLocalizedString("mtr.copy", comment: ""), target: self, action: #selector(copyResults))
        copyButton.bezelStyle = .rounded
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(copyButton)

        let exportButton = NSButton(title: NSLocalizedString("mtr.export", comment: ""), target: self, action: #selector(exportCSV))
        exportButton.bezelStyle = .rounded
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(exportButton)

        // Layout
        NSLayoutConstraint.activate([
            targetLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            targetLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            targetField.centerYAnchor.constraint(equalTo: targetLabel.centerYAnchor),
            targetField.leadingAnchor.constraint(equalTo: targetLabel.trailingAnchor, constant: 8),
            targetField.widthAnchor.constraint(equalToConstant: 200),

            startButton.centerYAnchor.constraint(equalTo: targetLabel.centerYAnchor),
            startButton.leadingAnchor.constraint(equalTo: targetField.trailingAnchor, constant: 12),

            stopButton.centerYAnchor.constraint(equalTo: targetLabel.centerYAnchor),
            stopButton.leadingAnchor.constraint(equalTo: startButton.trailingAnchor, constant: 8),

            progressIndicator.centerYAnchor.constraint(equalTo: targetLabel.centerYAnchor),
            progressIndicator.leadingAnchor.constraint(equalTo: stopButton.trailingAnchor, constant: 12),

            statusLabel.centerYAnchor.constraint(equalTo: targetLabel.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: targetLabel.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -12),

            copyButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            copyButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            exportButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            exportButton.leadingAnchor.constraint(equalTo: copyButton.trailingAnchor, constant: 8),
        ])
    }

    // MARK: - Actions

    @objc private func startMTR() {
        let target = targetField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }

        targetHost = target
        hops.removeAll()
        tableView.reloadData()

        startButton.isEnabled = false
        stopButton.isEnabled = true
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = NSLocalizedString("mtr.discovering", comment: "")

        // Phase 1 : Traceroute initial
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performInitialTraceroute()
        }
    }

    @objc private func stopMTR() {
        isRunning = false
        pingTimer?.invalidate()
        pingTimer = nil

        startButton.isEnabled = true
        stopButton.isEnabled = false
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        statusLabel.stringValue = NSLocalizedString("mtr.stopped", comment: "")
    }

    private func performInitialTraceroute() {
        // Résoudre l'adresse cible
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM

        var infoPtr: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(targetHost, nil, &hints, &infoPtr) == 0, infoPtr != nil else {
            DispatchQueue.main.async { [weak self] in
                self?.showError(NSLocalizedString("mtr.error.resolve", comment: ""))
            }
            return
        }
        defer { freeaddrinfo(infoPtr) }

        // Découvrir les hops
        var discoveredHops: [MTRHop] = []

        for ttl in 1...maxTTL {
            if let hopIP = probeHop(ttl: ttl) {
                let hop = MTRHop(hopNumber: ttl, ipAddress: hopIP)
                discoveredHops.append(hop)

                // Mettre à jour l'UI
                DispatchQueue.main.async { [weak self] in
                    self?.hops = discoveredHops
                    self?.tableView.reloadData()
                }

                // Si on a atteint la destination
                if hopIP == targetHost || isTargetReached(hopIP) {
                    break
                }
            } else {
                // Timeout - ajouter quand même le hop
                let hop = MTRHop(hopNumber: ttl, ipAddress: "*")
                discoveredHops.append(hop)

                DispatchQueue.main.async { [weak self] in
                    self?.hops = discoveredHops
                    self?.tableView.reloadData()
                }
            }
        }

        // Phase 2 : Résoudre les hostnames en arrière-plan
        for hop in discoveredHops where hop.ipAddress != "*" {
            resolveHostname(for: hop)
        }

        // Phase 3 : Démarrer le ping continu
        DispatchQueue.main.async { [weak self] in
            self?.hops = discoveredHops
            self?.tableView.reloadData()
            self?.startContinuousPing()
        }
    }

    private func probeHop(ttl: Int) -> String? {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard sock >= 0 else { return nil }
        defer { Darwin.close(sock) }

        // Timeout court pour éviter les réponses parasites
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // TTL
        var ttlValue = Int32(ttl)
        setsockopt(sock, IPPROTO_IP, IP_TTL, &ttlValue, socklen_t(MemoryLayout<Int32>.size))

        // Résoudre l'adresse
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var infoPtr: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(targetHost, nil, &hints, &infoPtr) == 0, let info = infoPtr else { return nil }
        defer { freeaddrinfo(infoPtr) }

        // Paquet ICMP avec identifiant unique pour cette session
        var packet = [UInt8](repeating: 0, count: 64)
        packet[0] = 8  // Echo Request
        let pid = UInt16(getpid() & 0xFFFF)
        packet[4] = UInt8(pid >> 8)
        packet[5] = UInt8(pid & 0xFF)
        let seq = UInt16(ttl)
        packet[6] = UInt8(seq >> 8)
        packet[7] = UInt8(seq & 0xFF)

        // Checksum
        var sum: UInt32 = 0
        for i in stride(from: 0, to: packet.count, by: 2) {
            sum += UInt32(packet[i]) << 8 | UInt32(packet[i+1])
        }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        let checksum = ~UInt16(sum)
        packet[2] = UInt8(checksum >> 8)
        packet[3] = UInt8(checksum & 0xFF)

        // Envoyer
        let sent = packet.withUnsafeBytes { buf in
            sendto(sock, buf.baseAddress, buf.count, 0, info.pointee.ai_addr, socklen_t(info.pointee.ai_addrlen))
        }
        guard sent > 0 else { return nil }

        // Recevoir avec validation
        var recvBuf = [UInt8](repeating: 0, count: 1024)
        var srcAddr = sockaddr_in()
        var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        // Essayer plusieurs fois de recevoir une réponse valide
        for _ in 0..<3 {
            let recvLen = withUnsafeMutablePointer(to: &srcAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(sock, &recvBuf, recvBuf.count, 0, sa, &srcLen)
                }
            }

            guard recvLen > 20 else { continue }  // Minimum IP header (20) + ICMP

            // Le buffer contient : IP header (20 bytes) + ICMP message
            let ipHeaderLen = Int(recvBuf[0] & 0x0F) * 4
            guard recvLen > ipHeaderLen + 8 else { continue }

            let icmpType = recvBuf[ipHeaderLen]
            let icmpCode = recvBuf[ipHeaderLen + 1]

            // Type 0 = Echo Reply (destination atteinte)
            if icmpType == 0 {
                let recvId = UInt16(recvBuf[ipHeaderLen + 4]) << 8 | UInt16(recvBuf[ipHeaderLen + 5])
                let recvSeq = UInt16(recvBuf[ipHeaderLen + 6]) << 8 | UInt16(recvBuf[ipHeaderLen + 7])
                if recvId == pid && recvSeq == seq {
                    var ipStr = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    inet_ntop(AF_INET, &srcAddr.sin_addr, &ipStr, socklen_t(INET_ADDRSTRLEN))
                    return String(cString: ipStr)
                }
            }
            // Type 11 = Time Exceeded (hop intermédiaire)
            else if icmpType == 11 && icmpCode == 0 {
                // Le paquet original est encapsulé après le header ICMP (8 bytes)
                // Structure: ICMP header (8) + Original IP header (variable) + Original ICMP header (8)
                let origIpStart = ipHeaderLen + 8  // Début de l'en-tête IP original
                guard recvLen > origIpStart + 20 else { continue }  // Au moins l'en-tête IP minimal

                // Lire le IHL de l'en-tête IP original (bits 0-3 du premier octet)
                let origIpHeaderLen = Int(recvBuf[origIpStart] & 0x0F) * 4
                guard origIpHeaderLen >= 20 && origIpHeaderLen <= 60 else { continue }  // IHL valide

                let originalOffset = origIpStart + origIpHeaderLen  // Position du header ICMP original
                guard recvLen > originalOffset + 8 else { continue }

                let origId = UInt16(recvBuf[originalOffset + 4]) << 8 | UInt16(recvBuf[originalOffset + 5])
                let origSeq = UInt16(recvBuf[originalOffset + 6]) << 8 | UInt16(recvBuf[originalOffset + 7])

                if origId == pid && origSeq == seq {
                    var ipStr = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    inet_ntop(AF_INET, &srcAddr.sin_addr, &ipStr, socklen_t(INET_ADDRSTRLEN))
                    return String(cString: ipStr)
                }
            }
            // Réponse non correspondante, continuer à attendre
        }

        return nil
    }

    private func isTargetReached(_ ip: String) -> Bool {
        // Comparer avec la résolution de la cible
        var hints = addrinfo()
        hints.ai_family = AF_INET
        var infoPtr: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(targetHost, nil, &hints, &infoPtr) == 0, let info = infoPtr else { return false }
        defer { freeaddrinfo(infoPtr) }

        let addr = info.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
        var targetIP = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var addrCopy = addr.sin_addr
        inet_ntop(AF_INET, &addrCopy, &targetIP, socklen_t(INET_ADDRSTRLEN))

        return ip == String(cString: targetIP)
    }

    private func resolveHostname(for hop: MTRHop) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            inet_pton(AF_INET, hop.ipAddress, &addr.sin_addr)

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    getnameinfo(sa, socklen_t(MemoryLayout<sockaddr_in>.size),
                               &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NAMEREQD)
                }
            }

            if result == 0 {
                let name = String(cString: hostname)
                DispatchQueue.main.async {
                    hop.hostname = name
                    self?.tableView.reloadData()
                }
            }
        }
    }

    private func startContinuousPing() {
        isRunning = true
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        statusLabel.stringValue = NSLocalizedString("mtr.running", comment: "")

        pingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pingAllHops()
        }
        pingAllHops()
    }

    private func pingAllHops() {
        guard isRunning else { return }

        let hopsToTest = hops.filter { $0.ipAddress != "*" }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for hop in hopsToTest {
                guard self?.isRunning == true else { break }

                hop.sentCount += 1
                if let latency = self?.pingHost(hop.ipAddress) {
                    hop.latencies.append(latency)
                    if hop.latencies.count > (self?.maxLatencies ?? 100) {
                        hop.latencies.removeFirst()
                    }
                } else {
                    hop.timeoutCount += 1
                }
            }

            DispatchQueue.main.async {
                self?.tableView.reloadData()
            }
        }
    }

    private func pingHost(_ host: String, timeout: TimeInterval = 1.0) -> Double? {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard sock >= 0 else { return nil }
        defer { Darwin.close(sock) }

        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout.truncatingRemainder(dividingBy: 1)) * 1_000_000))
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
        let seq = UInt16.random(in: 0...UInt16.max)
        packet[6] = UInt8(seq >> 8)
        packet[7] = UInt8(seq & 0xFF)

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

        // Essayer plusieurs fois de recevoir une réponse valide
        for _ in 0..<3 {
            let recvLen = withUnsafeMutablePointer(to: &srcAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(sock, &recvBuf, recvBuf.count, 0, sa, &srcLen)
                }
            }

            guard recvLen > 20 else { continue }

            let ipHeaderLen = Int(recvBuf[0] & 0x0F) * 4
            guard recvLen > ipHeaderLen + 8 else { continue }

            let icmpType = recvBuf[ipHeaderLen]

            // Type 0 = Echo Reply
            if icmpType == 0 {
                let recvId = UInt16(recvBuf[ipHeaderLen + 4]) << 8 | UInt16(recvBuf[ipHeaderLen + 5])
                let recvSeq = UInt16(recvBuf[ipHeaderLen + 6]) << 8 | UInt16(recvBuf[ipHeaderLen + 7])
                if recvId == pid && recvSeq == seq {
                    return (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                }
            }
        }
        return nil
    }

    private func showError(_ message: String) {
        stopMTR()
        statusLabel.stringValue = "✗ " + message
        statusLabel.textColor = .systemRed
    }

    // MARK: - Export

    @objc private func copyResults() {
        var text = "MTR → \(targetHost)\n"
        text += String(repeating: "─", count: 60) + "\n"
        text += String(format: "%3s  %-15s  %-20s  %5s  %5s  %6s  %6s  %6s  %6s\n",
                      "#", "IP", "Hostname", "Sent", "Loss%", "Avg", "Min", "Max", "Jitter")

        for hop in hops {
            let hostname = hop.hostname ?? ""
            text += String(format: "%3d  %-15s  %-20s  %5d  %5.1f%%  %6.1f  %6.1f  %6.1f  %6.1f\n",
                          hop.hopNumber,
                          hop.ipAddress,
                          String(hostname.prefix(20)),
                          hop.sentCount,
                          hop.lossPercent,
                          hop.avgLatency,
                          hop.minLatency,
                          hop.maxLatency,
                          hop.jitter)
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "mtr_\(targetHost)_\(Date().ISO8601Format()).csv"

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }

            var csv = "Hop,IP,Hostname,Sent,Received,Loss%,Avg ms,Min ms,Max ms,Jitter ms\n"
            for hop in self?.hops ?? [] {
                csv += "\(hop.hopNumber),\(hop.ipAddress),\(hop.hostname ?? ""),"
                csv += "\(hop.sentCount),\(hop.receivedCount),"
                csv += String(format: "%.1f,%.1f,%.1f,%.1f,%.1f\n",
                             hop.lossPercent, hop.avgLatency, hop.minLatency, hop.maxLatency, hop.jitter)
            }

            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Cleanup

    override func close() {
        stopMTR()
        super.close()
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension MTRWindowController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return hops.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < hops.count else { return nil }
        let hop = hops[row]

        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("")
        let cellIdentifier = NSUserInterfaceItemIdentifier("MTRCell_\(identifier.rawValue)")

        let textField: NSTextField
        if let existing = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTextField {
            textField = existing
        } else {
            textField = NSTextField(labelWithString: "")
            textField.identifier = cellIdentifier
            textField.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        }

        switch identifier.rawValue {
        case "hop":
            textField.stringValue = "\(hop.hopNumber)"
            textField.textColor = .secondaryLabelColor
        case "ip":
            textField.stringValue = hop.ipAddress
            textField.textColor = hop.ipAddress == "*" ? .tertiaryLabelColor : .labelColor
        case "hostname":
            textField.stringValue = hop.hostname ?? ""
            textField.font = NSFont.systemFont(ofSize: 11)
            textField.textColor = .secondaryLabelColor
        case "sent":
            textField.stringValue = hop.ipAddress == "*" ? "—" : "\(hop.sentCount)"
        case "loss":
            if hop.ipAddress == "*" {
                textField.stringValue = "—"
                textField.textColor = .tertiaryLabelColor
            } else {
                let loss = hop.lossPercent
                textField.stringValue = String(format: "%.1f%%", loss)
                textField.textColor = loss > 10 ? .systemRed : (loss > 0 ? .systemOrange : .labelColor)
            }
        case "avg":
            textField.stringValue = hop.latencies.isEmpty ? "—" : String(format: "%.1f", hop.avgLatency)
        case "min":
            textField.stringValue = hop.latencies.isEmpty ? "—" : String(format: "%.1f", hop.minLatency)
        case "max":
            textField.stringValue = hop.latencies.isEmpty ? "—" : String(format: "%.1f", hop.maxLatency)
        case "jitter":
            textField.stringValue = hop.latencies.count < 2 ? "—" : String(format: "%.1f", hop.jitter)
        default:
            textField.stringValue = ""
        }

        return textField
    }
}

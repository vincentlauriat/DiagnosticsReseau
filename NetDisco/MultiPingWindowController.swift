// MultiPingWindowController.swift
// NetDisco
//
// Ping simultané vers plusieurs cibles avec graphe comparatif.
// Affiche les statistiques de latence, jitter et perte pour chaque cible.

import Cocoa
import Darwin
import SystemConfiguration

// MARK: - Ping Target

struct PingTarget: Identifiable {
    let id: String
    var name: String
    var host: String
    var isEnabled: Bool
    var color: NSColor

    // Stats calculées
    var latencies: [Double?] = []

    var avgLatency: Double {
        let valid = latencies.compactMap { $0 }
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0, +) / Double(valid.count)
    }

    var minLatency: Double {
        latencies.compactMap { $0 }.min() ?? 0
    }

    var maxLatency: Double {
        latencies.compactMap { $0 }.max() ?? 0
    }

    var jitter: Double {
        let valid = latencies.compactMap { $0 }
        guard valid.count > 1 else { return 0 }
        var diffs: [Double] = []
        for i in 1..<valid.count {
            diffs.append(abs(valid[i] - valid[i-1]))
        }
        return diffs.reduce(0, +) / Double(diffs.count)
    }

    var lossPercent: Double {
        guard !latencies.isEmpty else { return 0 }
        let lost = latencies.filter { $0 == nil }.count
        return Double(lost) / Double(latencies.count) * 100
    }
}

// MARK: - MultiPingWindowController

class MultiPingWindowController: NSWindowController {

    // UI
    private var graphView: MultiTargetGraphView!
    private var statsTableView: NSTableView!
    private var customHostField: NSTextField!
    private var startStopButton: NSButton!
    private var statusLabel: NSTextField!
    private var checkboxes: [String: NSButton] = [:]
    private var packetCount = 0

    // State
    private let targetsLock = NSLock()
    private var targets: [PingTarget] = []
    private var pingTimer: Timer?
    private var isRunning = false
    private let maxSamples = 120

    // Default targets
    private let defaultTargets: [(id: String, name: String, host: String, color: NSColor)] = [
        ("google", "Google DNS", "8.8.8.8", .systemBlue),
        ("cloudflare", "Cloudflare DNS", "1.1.1.1", .systemOrange),
        ("gateway", NSLocalizedString("multiping.gateway", comment: ""), "", .systemGreen),
        ("custom", NSLocalizedString("multiping.custom", comment: ""), "", .systemPurple)
    ]

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("multiping.title", comment: "")
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 550, height: 500)
        self.init(window: window)
        setupUI()
        setupTargets()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        // === Section Cibles ===
        let targetTitleLabel = NSTextField(labelWithString: NSLocalizedString("multiping.targets", comment: ""))
        targetTitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        targetTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(targetTitleLabel)

        // Conteneur pour les checkboxes avec bordure
        let targetContainer = NSView()
        targetContainer.wantsLayer = true
        targetContainer.layer?.borderWidth = 1
        targetContainer.layer?.borderColor = NSColor.separatorColor.cgColor
        targetContainer.layer?.cornerRadius = 6
        targetContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(targetContainer)

        // Stack vertical pour les lignes de cibles
        let targetStack = NSStackView()
        targetStack.orientation = .vertical
        targetStack.alignment = .leading
        targetStack.spacing = 10
        targetStack.translatesAutoresizingMaskIntoConstraints = false
        targetContainer.addSubview(targetStack)

        // Créer les lignes pour chaque cible
        for target in defaultTargets {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 10
            row.alignment = .centerY

            // Checkbox
            let checkbox = NSButton(checkboxWithTitle: target.name, target: self, action: #selector(targetCheckboxChanged))
            checkbox.state = target.id != "custom" ? .on : .off
            checkbox.tag = defaultTargets.firstIndex(where: { $0.id == target.id }) ?? 0
            checkboxes[target.id] = checkbox
            row.addArrangedSubview(checkbox)

            // Indicateur de couleur
            let colorDot = NSView()
            colorDot.wantsLayer = true
            colorDot.layer?.backgroundColor = target.color.cgColor
            colorDot.layer?.cornerRadius = 5
            colorDot.translatesAutoresizingMaskIntoConstraints = false
            row.addArrangedSubview(colorDot)
            NSLayoutConstraint.activate([
                colorDot.widthAnchor.constraint(equalToConstant: 10),
                colorDot.heightAnchor.constraint(equalToConstant: 10)
            ])

            // Champ texte pour cible personnalisée ou affichage host
            if target.id == "custom" {
                customHostField = NSTextField()
                customHostField.placeholderString = "one.one.one.one"
                customHostField.translatesAutoresizingMaskIntoConstraints = false
                customHostField.delegate = self
                row.addArrangedSubview(customHostField)
                customHostField.widthAnchor.constraint(equalToConstant: 180).isActive = true
            } else if !target.host.isEmpty {
                let hostLabel = NSTextField(labelWithString: "(\(target.host))")
                hostLabel.font = NSFont.systemFont(ofSize: 11)
                hostLabel.textColor = .secondaryLabelColor
                row.addArrangedSubview(hostLabel)
            }

            targetStack.addArrangedSubview(row)
        }

        // === Bouton Démarrer/Arrêter ===
        startStopButton = NSButton(title: NSLocalizedString("multiping.start", comment: ""), target: self, action: #selector(togglePing))
        startStopButton.bezelStyle = .rounded
        startStopButton.controlSize = .large
        startStopButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(startStopButton)

        // === Label de statut ===
        statusLabel = NSTextField(labelWithString: NSLocalizedString("multiping.status.ready", comment: ""))
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusLabel)

        // === Graphe ===
        graphView = MultiTargetGraphView()
        graphView.yAxisLabel = "ms"
        graphView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(graphView)

        // === Tableau des stats ===
        let statsLabel = NSTextField(labelWithString: NSLocalizedString("multiping.stats", comment: ""))
        statsLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statsLabel)

        let statsScroll = NSScrollView()
        statsScroll.hasVerticalScroller = true
        statsScroll.borderType = .bezelBorder
        statsScroll.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statsScroll)

        statsTableView = NSTableView()
        statsTableView.dataSource = self
        statsTableView.delegate = self
        statsTableView.rowHeight = 22
        statsTableView.usesAlternatingRowBackgroundColors = true

        let cols: [(String, String, CGFloat)] = [
            ("target", NSLocalizedString("multiping.col.target", comment: ""), 120),
            ("avg", NSLocalizedString("multiping.col.avg", comment: ""), 70),
            ("min", NSLocalizedString("multiping.col.min", comment: ""), 60),
            ("max", NSLocalizedString("multiping.col.max", comment: ""), 60),
            ("jitter", NSLocalizedString("multiping.col.jitter", comment: ""), 70),
            ("loss", NSLocalizedString("multiping.col.loss", comment: ""), 60)
        ]

        for (id, title, width) in cols {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            statsTableView.addTableColumn(col)
        }

        statsScroll.documentView = statsTableView

        // === Bouton Copier ===
        let copyButton = NSButton(title: NSLocalizedString("multiping.copy", comment: ""), target: self, action: #selector(copyStats))
        copyButton.bezelStyle = .rounded
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(copyButton)

        // === Layout ===
        NSLayoutConstraint.activate([
            // Titre des cibles
            targetTitleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            targetTitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            // Conteneur des cibles
            targetContainer.topAnchor.constraint(equalTo: targetTitleLabel.bottomAnchor, constant: 8),
            targetContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            targetContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            // Stack dans le conteneur
            targetStack.topAnchor.constraint(equalTo: targetContainer.topAnchor, constant: 12),
            targetStack.leadingAnchor.constraint(equalTo: targetContainer.leadingAnchor, constant: 12),
            targetStack.trailingAnchor.constraint(lessThanOrEqualTo: targetContainer.trailingAnchor, constant: -12),
            targetStack.bottomAnchor.constraint(equalTo: targetContainer.bottomAnchor, constant: -12),

            // Bouton démarrer
            startStopButton.topAnchor.constraint(equalTo: targetContainer.bottomAnchor, constant: 16),
            startStopButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            startStopButton.widthAnchor.constraint(equalToConstant: 140),

            // Label statut
            statusLabel.topAnchor.constraint(equalTo: startStopButton.bottomAnchor, constant: 8),
            statusLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            // Graphe
            graphView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            graphView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            graphView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            graphView.heightAnchor.constraint(equalToConstant: 180),

            // Label stats
            statsLabel.topAnchor.constraint(equalTo: graphView.bottomAnchor, constant: 16),
            statsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            // Tableau stats
            statsScroll.topAnchor.constraint(equalTo: statsLabel.bottomAnchor, constant: 8),
            statsScroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            statsScroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            statsScroll.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -16),
            statsScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),

            // Bouton copier
            copyButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            copyButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)
        ])
    }

    private func setupTargets() {
        targetsLock.lock()
        for target in defaultTargets {
            var host = target.host
            if target.id == "gateway" {
                host = getDefaultGateway() ?? ""
            }
            targets.append(PingTarget(
                id: target.id,
                name: target.name,
                host: host,
                isEnabled: target.id != "custom",
                color: target.color
            ))
        }
        targetsLock.unlock()
        updateGraphTargets()
    }

    private func updateGraphTargets() {
        var graphTargets: [GraphTarget] = []
        for target in targets where target.isEnabled && !target.host.isEmpty {
            graphTargets.append(GraphTarget(
                id: target.id,
                name: target.name,
                color: target.color,
                samples: target.latencies
            ))
        }
        graphView.setTargets(graphTargets)
    }

    // MARK: - Actions

    @objc private func targetCheckboxChanged(_ sender: NSButton) {
        let index = sender.tag
        targetsLock.lock()
        guard index < targets.count else {
            targetsLock.unlock()
            return
        }
        targets[index].isEnabled = sender.state == .on

        // Pour custom, mettre à jour le host
        if targets[index].id == "custom" {
            targets[index].host = customHostField.stringValue.trimmingCharacters(in: .whitespaces)
        }
        targetsLock.unlock()

        updateGraphTargets()
    }

    @objc private func togglePing() {
        if isRunning {
            stopPing()
        } else {
            startPing()
        }
    }

    private func startPing() {
        targetsLock.lock()

        // Mettre à jour le host custom si nécessaire
        if let idx = targets.firstIndex(where: { $0.id == "custom" }) {
            targets[idx].host = customHostField.stringValue.trimmingCharacters(in: .whitespaces)
        }

        // Mettre à jour la gateway si nécessaire
        if let idx = targets.firstIndex(where: { $0.id == "gateway" }) {
            targets[idx].host = getDefaultGateway() ?? ""
        }

        // Vérifier qu'au moins une cible est active
        let activeTargets = targets.filter { $0.isEnabled && !$0.host.isEmpty }
        guard !activeTargets.isEmpty else {
            targetsLock.unlock()
            statusLabel.stringValue = NSLocalizedString("multiping.status.no_target", comment: "")
            statusLabel.textColor = .systemOrange
            return
        }

        // Reset latencies et compteur
        for i in targets.indices {
            targets[i].latencies.removeAll()
        }
        targetsLock.unlock()

        packetCount = 0

        isRunning = true
        startStopButton.title = NSLocalizedString("multiping.stop", comment: "")
        statusLabel.stringValue = NSLocalizedString("multiping.status.starting", comment: "")
        statusLabel.textColor = .secondaryLabelColor
        updateGraphTargets()

        // Timer à 1 Hz
        pingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.performPingCycle()
        }
        performPingCycle()
    }

    private func stopPing() {
        pingTimer?.invalidate()
        pingTimer = nil
        isRunning = false
        startStopButton.title = NSLocalizedString("multiping.start", comment: "")
        statusLabel.stringValue = NSLocalizedString("multiping.status.stopped", comment: "")
        statusLabel.textColor = .secondaryLabelColor
    }

    private func performPingCycle() {
        let group = DispatchGroup()
        var results: [(String, Double?)] = []
        let lock = NSLock()

        // Capture immutable snapshot for background threads
        targetsLock.lock()
        let targetsSnapshot = targets.filter { $0.isEnabled && !$0.host.isEmpty }
        targetsLock.unlock()

        for target in targetsSnapshot {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let latency = self.ping(host: target.host)
                lock.lock()
                results.append((target.id, latency))
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self, self.isRunning else { return }

            self.packetCount += 1

            self.targetsLock.lock()
            for (targetId, latency) in results {
                if let idx = self.targets.firstIndex(where: { $0.id == targetId }) {
                    self.targets[idx].latencies.append(latency)
                    if self.targets[idx].latencies.count > self.maxSamples {
                        self.targets[idx].latencies.removeFirst()
                    }
                }
            }
            self.targetsLock.unlock()

            // Update status
            self.statusLabel.stringValue = String(format: NSLocalizedString("multiping.status.running", comment: ""), self.packetCount)
            self.statusLabel.textColor = .systemGreen

            // Update graph
            self.graphView.addSamples(results.map { (targetId: $0.0, value: $0.1) })
            self.statsTableView.reloadData()
        }
    }

    // MARK: - ICMP Ping

    private func ping(host: String, timeout: TimeInterval = 2.0) -> Double? {
        // Résoudre l'adresse
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM

        var infoPtr: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &infoPtr) == 0, let info = infoPtr else { return nil }
        defer { freeaddrinfo(infoPtr) }

        // Créer le socket ICMP
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard sock >= 0 else { return nil }
        defer { Darwin.close(sock) }

        // Timeout
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout.truncatingRemainder(dividingBy: 1)) * 1_000_000))
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Construire le paquet ICMP Echo Request
        var packet = [UInt8](repeating: 0, count: 64)
        packet[0] = 8  // Type: Echo Request
        packet[1] = 0  // Code
        // Checksum à [2-3]
        let pid = UInt16(getpid() & 0xFFFF)
        packet[4] = UInt8(pid >> 8)
        packet[5] = UInt8(pid & 0xFF)
        let seq = UInt16.random(in: 0...UInt16.max)
        packet[6] = UInt8(seq >> 8)
        packet[7] = UInt8(seq & 0xFF)

        // Calcul du checksum
        var sum: UInt32 = 0
        for i in stride(from: 0, to: packet.count, by: 2) {
            let word = UInt32(packet[i]) << 8 | UInt32(packet[i+1])
            sum += word
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        let checksum = ~UInt16(sum)
        packet[2] = UInt8(checksum >> 8)
        packet[3] = UInt8(checksum & 0xFF)

        // Envoyer
        let startTime = CFAbsoluteTimeGetCurrent()
        let sent = packet.withUnsafeBytes { buf in
            sendto(sock, buf.baseAddress, buf.count, 0, info.pointee.ai_addr, socklen_t(info.pointee.ai_addrlen))
        }
        guard sent == packet.count else { return nil }

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

            guard recvLen > 20 else { continue }

            // Parser l'en-tête IP pour trouver l'ICMP
            let ipHeaderLen = Int(recvBuf[0] & 0x0F) * 4
            guard recvLen > ipHeaderLen + 8 else { continue }

            let icmpType = recvBuf[ipHeaderLen]

            // Type 0 = Echo Reply
            if icmpType == 0 {
                let recvId = UInt16(recvBuf[ipHeaderLen + 4]) << 8 | UInt16(recvBuf[ipHeaderLen + 5])
                let recvSeq = UInt16(recvBuf[ipHeaderLen + 6]) << 8 | UInt16(recvBuf[ipHeaderLen + 7])
                if recvId == pid && recvSeq == seq {
                    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                    return elapsed
                }
            }
            // Réponse non correspondante, continuer à attendre
        }
        return nil
    }

    // MARK: - Network Helpers

    private func getDefaultGateway() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "NetDisco" as CFString, nil, nil),
              let config = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let router = config["Router"] as? String else { return nil }
        return router
    }

    // MARK: - Copy

    @objc private func copyStats() {
        var text = NSLocalizedString("multiping.title", comment: "") + "\n"
        text += String(repeating: "─", count: 50) + "\n"

        for target in targets where target.isEnabled && !target.host.isEmpty {
            text += "\(target.name) (\(target.host))\n"
            text += String(format: "  Moy: %.1f ms  Min: %.1f ms  Max: %.1f ms\n", target.avgLatency, target.minLatency, target.maxLatency)
            text += String(format: "  Jitter: %.1f ms  Perte: %.1f%%\n\n", target.jitter, target.lossPercent)
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Cleanup

    override func close() {
        stopPing()
        super.close()
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension MultiPingWindowController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        targetsLock.lock()
        let count = targets.filter { $0.isEnabled && !$0.host.isEmpty }.count
        targetsLock.unlock()
        return count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        targetsLock.lock()
        let activeTargets = targets.filter { $0.isEnabled && !$0.host.isEmpty }
        guard row < activeTargets.count else {
            targetsLock.unlock()
            return nil
        }
        let target = activeTargets[row]
        targetsLock.unlock()

        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("")
        let cellIdentifier = NSUserInterfaceItemIdentifier("MultiPingCell_\(identifier.rawValue)")

        let textField: NSTextField
        if let existing = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTextField {
            textField = existing
        } else {
            textField = NSTextField(labelWithString: "")
            textField.identifier = cellIdentifier
            textField.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        }

        switch identifier.rawValue {
        case "target":
            textField.stringValue = target.name
            textField.textColor = target.color
            textField.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        case "avg":
            textField.stringValue = target.latencies.isEmpty ? "—" : String(format: "%.1f ms", target.avgLatency)
        case "min":
            textField.stringValue = target.latencies.isEmpty ? "—" : String(format: "%.1f ms", target.minLatency)
        case "max":
            textField.stringValue = target.latencies.isEmpty ? "—" : String(format: "%.1f ms", target.maxLatency)
        case "jitter":
            textField.stringValue = target.latencies.count < 2 ? "—" : String(format: "%.1f ms", target.jitter)
        case "loss":
            let loss = target.lossPercent
            textField.stringValue = target.latencies.isEmpty ? "—" : String(format: "%.1f%%", loss)
            textField.textColor = loss > 5 ? .systemRed : (loss > 0 ? .systemOrange : .labelColor)
        default:
            textField.stringValue = ""
        }

        return textField
    }
}

// MARK: - NSTextFieldDelegate

extension MultiPingWindowController: NSTextFieldDelegate {

    func controlTextDidChange(_ obj: Notification) {
        // Auto-activer la cible custom quand l'utilisateur tape
        guard let textField = obj.object as? NSTextField,
              textField === customHostField else { return }

        let text = textField.stringValue.trimmingCharacters(in: .whitespaces)

        // Si du texte est entré, cocher automatiquement la checkbox custom
        if !text.isEmpty {
            if let checkbox = checkboxes["custom"] {
                checkbox.state = .on
            }
            targetsLock.lock()
            if let idx = targets.firstIndex(where: { $0.id == "custom" }) {
                targets[idx].isEnabled = true
                targets[idx].host = text
            }
            targetsLock.unlock()
        }

        updateGraphTargets()
    }
}

// NetworkDetailWindowController.swift
// NetDisco
//
// Fenêtre split-view affichant les informations réseau détaillées :
//   - Panneau gauche (sidebar) : liste des sections avec icônes SF Symbols
//   - Panneau droit : détail formaté de la section sélectionnée
// Sections : état de connexion (NWPathMonitor), interfaces réseau (ifaddrs/ioctl),
// WiFi (CoreWLAN), routage (SCDynamicStore), DNS (SystemConfiguration),
// IP publique (ipify.org / api6.ipify.org).
// Rafraîchissement automatique toutes les 5 secondes.

import Cocoa
import Network
import SystemConfiguration
import CoreWLAN

class NetworkDetailWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSplitViewDelegate {

    private var splitView: NSSplitView!
    private var sidebarTableView: NSTableView!
    private var detailScrollView: NSScrollView!
    private var detailTextView: NSTextView!
    private var refreshTimer: Timer?

    private var sections: [(section: String, icon: String, items: [(String, String)])] = []
    private var previousByteCounters: [String: (bytesIn: UInt64, bytesOut: UInt64, time: Date)] = [:]
    private var throughputCache: [String: (inRate: String, outRate: String)] = [:]

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("details.title", comment: "")
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 400)

        self.init(window: window)
        setupUI()
        refresh()
        startAutoRefresh()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // --- Split View ---
        splitView = NSSplitView()
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        contentView.addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: contentView.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        // --- Sidebar (left) ---
        let sidebarScroll = NSScrollView()
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.autohidesScrollers = true
        sidebarScroll.borderType = .noBorder
        sidebarScroll.autoresizingMask = [.width, .height]

        sidebarTableView = NSTableView()
        sidebarTableView.headerView = nil
        sidebarTableView.style = .sourceList
        sidebarTableView.rowHeight = 28
        sidebarTableView.dataSource = self
        sidebarTableView.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Section"))
        column.title = ""
        sidebarTableView.addTableColumn(column)

        sidebarScroll.documentView = sidebarTableView
        splitView.addSubview(sidebarScroll)

        // --- Detail (right) ---
        let rightPane = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        rightPane.autoresizingMask = [.width, .height]

        // Toolbar with refresh + copy buttons
        let refreshButton = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: NSLocalizedString("netdetail.button.refresh", comment: ""))!, target: self, action: #selector(refreshClicked))
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.bezelStyle = .rounded
        refreshButton.isBordered = false
        refreshButton.toolTip = NSLocalizedString("netdetail.button.refresh", comment: "")
        rightPane.addSubview(refreshButton)

        let copyButton = NSButton(image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: NSLocalizedString("netdetail.button.copy", comment: ""))!, target: self, action: #selector(copyAllInfo))
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.bezelStyle = .rounded
        copyButton.isBordered = false
        copyButton.toolTip = NSLocalizedString("netdetail.button.copy_tooltip", comment: "")
        rightPane.addSubview(copyButton)

        detailScrollView = NSScrollView()
        detailScrollView.translatesAutoresizingMaskIntoConstraints = false
        detailScrollView.hasVerticalScroller = true
        detailScrollView.autohidesScrollers = true
        detailScrollView.borderType = .noBorder

        detailTextView = NSTextView()
        detailTextView.isEditable = false
        detailTextView.isSelectable = true
        detailTextView.textContainerInset = NSSize(width: 16, height: 16)
        detailTextView.autoresizingMask = [.width]
        detailTextView.isVerticallyResizable = true
        detailTextView.isHorizontallyResizable = false
        detailTextView.textContainer?.widthTracksTextView = true
        detailTextView.backgroundColor = .textBackgroundColor

        detailScrollView.documentView = detailTextView
        rightPane.addSubview(detailScrollView)

        NSLayoutConstraint.activate([
            refreshButton.topAnchor.constraint(equalTo: rightPane.topAnchor, constant: 6),
            refreshButton.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor, constant: -8),
            refreshButton.widthAnchor.constraint(equalToConstant: 24),
            refreshButton.heightAnchor.constraint(equalToConstant: 24),

            copyButton.topAnchor.constraint(equalTo: rightPane.topAnchor, constant: 6),
            copyButton.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor, constant: -4),
            copyButton.widthAnchor.constraint(equalToConstant: 24),
            copyButton.heightAnchor.constraint(equalToConstant: 24),

            detailScrollView.topAnchor.constraint(equalTo: refreshButton.bottomAnchor, constant: 4),
            detailScrollView.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor),
            detailScrollView.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor),
            detailScrollView.bottomAnchor.constraint(equalTo: rightPane.bottomAnchor),
        ])

        splitView.addSubview(rightPane)

        // Position the divider after layout
        DispatchQueue.main.async {
            self.splitView.setPosition(200, ofDividerAt: 0)
        }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // Select first row if nothing selected
        if sidebarTableView.selectedRow < 0 && sections.count > 0 {
            sidebarTableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    @objc private func refreshClicked() {
        refresh()
    }

    private func refresh() {
        let previousSelection = sidebarTableView.selectedRow
        sections = gatherNetworkInfo()
        sidebarTableView.reloadData()

        let row = (previousSelection >= 0 && previousSelection < sections.count) ? previousSelection : 0
        if sections.count > 0 {
            sidebarTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            showDetail(for: row)
        }
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellId = NSUserInterfaceItemIdentifier("SectionCell")
        let cell: NSTableCellView
        if let existing = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTableCellView {
            cell = existing
        } else {
            cell = NSTableCellView()
            cell.identifier = cellId

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imageView)
            cell.imageView = imageView

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.font = NSFont.systemFont(ofSize: 13)
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 18),
                imageView.heightAnchor.constraint(equalToConstant: 18),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        let section = sections[row]
        cell.textField?.stringValue = section.section
        if let img = NSImage(systemSymbolName: section.icon, accessibilityDescription: section.section) {
            cell.imageView?.image = img
            cell.imageView?.contentTintColor = .controlAccentColor
        }

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = sidebarTableView.selectedRow
        if row >= 0 && row < sections.count {
            showDetail(for: row)
        }
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return 160
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return 280
    }

    // MARK: - Detail Display

    private func showDetail(for row: Int) {
        let section = sections[row]
        let attributed = formatSection(section)
        detailTextView.textStorage?.setAttributedString(attributed)
        detailTextView.scrollToBeginningOfDocument(nil)
    }

    private static let ipv4Regex = try! NSRegularExpression(pattern: "\\b\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\b")
    private static let ipv6Regex = try! NSRegularExpression(pattern: "\\b[0-9a-fA-F:]{6,39}\\b")

    private func formatSection(_ section: (section: String, icon: String, items: [(String, String)])) -> NSAttributedString {
        let result = NSMutableAttributedString()

        let titleFont = NSFont.boldSystemFont(ofSize: 17)
        let labelFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        let valueFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        // Title
        result.append(NSAttributedString(string: section.section + "\n\n", attributes: [
            .font: titleFont,
            .foregroundColor: NSColor.labelColor,
        ]))

        // Items as aligned key-value pairs
        let maxLabelLen = section.items.map { $0.0.count }.max() ?? 0
        for (label, value) in section.items {
            let paddedLabel = label.padding(toLength: maxLabelLen + 3, withPad: " ", startingAt: 0)
            result.append(NSAttributedString(string: "  \(paddedLabel)", attributes: [
                .font: labelFont,
                .foregroundColor: NSColor.systemTeal,
            ]))

            // Coloriser les IPs en bleu dans les valeurs
            let attrValue = NSMutableAttributedString(string: value + "\n", attributes: [
                .font: valueFont,
                .foregroundColor: NSColor.labelColor,
            ])
            let nsValue = value as NSString
            let range = NSRange(location: 0, length: nsValue.length)
            for match in Self.ipv4Regex.matches(in: value, range: range) {
                attrValue.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: match.range)
            }
            for match in Self.ipv6Regex.matches(in: value, range: range) {
                let matched = nsValue.substring(with: match.range)
                if matched.contains(":") {
                    attrValue.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: match.range)
                }
            }
            result.append(attrValue)
        }

        return result
    }

    // MARK: - Gather Network Info

    /// Lit les compteurs d'octets par interface via getifaddrs (AF_LINK / sockaddr_dl).
    private func updateByteCounters() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }

        let now = Date()
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = cursor {
            let name = String(cString: addr.pointee.ifa_name)
            if let data = addr.pointee.ifa_data, addr.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) {
                let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                let bytesIn = UInt64(ifData.ifi_ibytes)
                let bytesOut = UInt64(ifData.ifi_obytes)

                if let prev = previousByteCounters[name] {
                    let dt = now.timeIntervalSince(prev.time)
                    if dt > 0 {
                        let inRate = Double(bytesIn &- prev.bytesIn) / dt
                        let outRate = Double(bytesOut &- prev.bytesOut) / dt
                        throughputCache[name] = (formatRate(inRate), formatRate(outRate))
                    }
                }
                previousByteCounters[name] = (bytesIn, bytesOut, now)
            }
            cursor = addr.pointee.ifa_next
        }
    }

    private func formatRate(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_000_000 {
            return String(format: "%.1f Mo/s", bytesPerSec / 1_000_000)
        } else if bytesPerSec >= 1_000 {
            return String(format: "%.1f Ko/s", bytesPerSec / 1_000)
        } else {
            return String(format: "%.0f o/s", bytesPerSec)
        }
    }

    private func gatherNetworkInfo() -> [(section: String, icon: String, items: [(String, String)])] {
        var result: [(section: String, icon: String, items: [(String, String)])] = []

        result.append((section: NSLocalizedString("details.section.connection", comment: ""), icon: "network", items: getConnectionStatus()))

        updateByteCounters()

        let interfaces = getNetworkInterfaces()
        let grouped = Dictionary(grouping: interfaces, by: { $0.name })
        let sortedNames = grouped.keys.sorted { a, b in
            let order = ["en0", "en1", "awdl0", "utun", "lo0"]
            let idxA = order.firstIndex(where: { a.hasPrefix($0) }) ?? 99
            let idxB = order.firstIndex(where: { b.hasPrefix($0) }) ?? 99
            return idxA < idxB
        }

        for name in sortedNames {
            guard let ifaces = grouped[name] else { continue }
            var items: [(String, String)] = []
            items.append(("Interface", name))

            if let type = getInterfaceType(name) {
                items.append(("Type", type))
            }

            let flags = getInterfaceFlags(name)
            items.append((NSLocalizedString("netdetail.label.status", comment: ""), flags.contains("UP") ? NSLocalizedString("netdetail.status.active", comment: "") : NSLocalizedString("netdetail.status.inactive", comment: "")))
            items.append(("Flags", flags))

            if let mtu = getInterfaceMTU(name) {
                items.append(("MTU", "\(mtu)"))
            }

            if let mac = getMACAddress(name) {
                items.append(("Adresse MAC", mac))
            }

            for iface in ifaces {
                let label = iface.family == "IPv4" ? "Adresse IPv4" : "Adresse IPv6"
                items.append((label, iface.address))
                if let netmask = iface.netmask {
                    items.append(("Masque", netmask))
                }
            }

            if let tp = throughputCache[name] {
                items.append((NSLocalizedString("netdetail.label.throughput_in", comment: ""), tp.inRate))
                items.append((NSLocalizedString("netdetail.label.throughput_out", comment: ""), tp.outRate))
            }

            let icon: String
            if name.hasPrefix("en") { icon = "antenna.radiowaves.left.and.right" }
            else if name.hasPrefix("lo") { icon = "arrow.triangle.2.circlepath" }
            else if name.hasPrefix("utun") { icon = "lock.shield" }
            else if name.hasPrefix("awdl") || name.hasPrefix("llw") { icon = "airplayaudio" }
            else if name.hasPrefix("bridge") { icon = "rectangle.connected.to.line.below" }
            else { icon = "cable.connector" }

            result.append((section: name, icon: icon, items: items))
        }

        if let wifiInfo = getWiFiInfo() {
            result.append((section: NSLocalizedString("details.section.wifi", comment: ""), icon: "wifi", items: wifiInfo))
        }

        result.append((section: NSLocalizedString("details.section.routing", comment: ""), icon: "arrow.triangle.branch", items: getRoutingInfo()))
        result.append((section: NSLocalizedString("details.section.dns", comment: ""), icon: "text.magnifyingglass", items: getDNSInfo()))
        result.append((section: NSLocalizedString("details.section.public_ip", comment: ""), icon: "globe", items: getPublicIP()))

        let vpnInfo = getVPNInfo()
        if !vpnInfo.isEmpty {
            result.insert((section: NSLocalizedString("details.section.vpn", comment: ""), icon: "lock.shield.fill", items: vpnInfo), at: 1)
        }

        return result
    }

    // MARK: - Connection Status

    private func getConnectionStatus() -> [(String, String)] {
        var items: [(String, String)] = []

        let monitor = NWPathMonitor()
        let semaphore = DispatchSemaphore(value: 0)
        var pathStatus: NWPath?

        monitor.pathUpdateHandler = { path in
            pathStatus = path
            semaphore.signal()
        }
        let queue = DispatchQueue(label: "StatusCheck")
        monitor.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + 2)
        monitor.cancel()

        if let path = pathStatus {
            items.append((NSLocalizedString("netdetail.label.internet", comment: ""), path.status == .satisfied ? NSLocalizedString("netdetail.value.connected", comment: "") : NSLocalizedString("netdetail.value.disconnected", comment: "")))
            items.append((NSLocalizedString("netdetail.label.expensive", comment: ""), path.isExpensive ? NSLocalizedString("netdetail.value.yes", comment: "") : NSLocalizedString("netdetail.value.no", comment: "")))
            items.append((NSLocalizedString("netdetail.label.constrained", comment: ""), path.isConstrained ? NSLocalizedString("netdetail.value.yes", comment: "") : NSLocalizedString("netdetail.value.no", comment: "")))

            if path.usesInterfaceType(.wifi) {
                items.append((NSLocalizedString("netdetail.label.active_type", comment: ""), "WiFi"))
            } else if path.usesInterfaceType(.wiredEthernet) {
                items.append((NSLocalizedString("netdetail.label.active_type", comment: ""), "Ethernet"))
            } else if path.usesInterfaceType(.cellular) {
                items.append((NSLocalizedString("netdetail.label.active_type", comment: ""), NSLocalizedString("netdetail.value.cellular", comment: "")))
            } else if path.usesInterfaceType(.loopback) {
                items.append((NSLocalizedString("netdetail.label.active_type", comment: ""), "Loopback"))
            } else {
                items.append((NSLocalizedString("netdetail.label.active_type", comment: ""), NSLocalizedString("netdetail.value.other", comment: "")))
            }

            items.append((NSLocalizedString("netdetail.label.supports_dns", comment: ""), path.supportsDNS ? NSLocalizedString("netdetail.value.yes", comment: "") : NSLocalizedString("netdetail.value.no", comment: "")))
            items.append((NSLocalizedString("netdetail.label.supports_ipv4", comment: ""), path.supportsIPv4 ? NSLocalizedString("netdetail.value.yes", comment: "") : NSLocalizedString("netdetail.value.no", comment: "")))
            items.append((NSLocalizedString("netdetail.label.supports_ipv6", comment: ""), path.supportsIPv6 ? NSLocalizedString("netdetail.value.yes", comment: "") : NSLocalizedString("netdetail.value.no", comment: "")))
        }

        // Uptime (24h)
        let uptime = UptimeTracker.uptimePercent24h()
        items.append((NSLocalizedString("netdetail.label.uptime_24h", comment: ""), String(format: "%.1f%%", uptime)))
        let disconnections = UptimeTracker.disconnectionCount24h()
        items.append((NSLocalizedString("netdetail.label.disconnections_24h", comment: ""), "\(disconnections)"))

        return items
    }

    private func detectActiveVPN() -> Bool {
        return !getVPNInfo().isEmpty
    }

    /// Détecte les interfaces VPN actives et retourne les détails (interface, type, adresses).
    private func getVPNInfo() -> [(String, String)] {
        var items: [(String, String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return items }
        defer { freeifaddrs(ifaddr) }

        // Collect VPN interfaces and their addresses
        struct VPNInterface {
            let name: String
            let type: String
            var ipv4: [String] = []
            var ipv6: [String] = []
        }

        var vpnMap: [String: VPNInterface] = [:]

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = cursor {
            defer { cursor = addr.pointee.ifa_next }
            let name = String(cString: addr.pointee.ifa_name)
            let flags = Int32(addr.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0 else { continue }
            guard let sa = addr.pointee.ifa_addr else { continue }
            let family = sa.pointee.sa_family

            let isVPN: Bool
            let vpnType: String
            if name.hasPrefix("utun") {
                // Only consider utun with IPv4 as VPN (system utun only have IPv6 link-local)
                if family == UInt8(AF_INET) {
                    isVPN = true
                    vpnType = "Tunnel (utun)"
                } else {
                    continue
                }
            } else if name.hasPrefix("ipsec") {
                isVPN = true
                vpnType = "IPSec"
            } else if name.hasPrefix("ppp") {
                isVPN = true
                vpnType = "PPP"
            } else {
                continue
            }

            guard isVPN else { continue }

            if vpnMap[name] == nil {
                vpnMap[name] = VPNInterface(name: name, type: vpnType)
            }

            if family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(sa, socklen_t(sa.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                vpnMap[name]?.ipv4.append(String(cString: hostname))
            } else if family == UInt8(AF_INET6) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(sa, socklen_t(sa.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                vpnMap[name]?.ipv6.append(String(cString: hostname))
            }

            // Get destination address (point-to-point)
            if flags & IFF_POINTOPOINT != 0, let dstAddr = addr.pointee.ifa_dstaddr {
                let dstFamily = dstAddr.pointee.sa_family
                if dstFamily == UInt8(AF_INET) || dstFamily == UInt8(AF_INET6) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(dstAddr, socklen_t(dstAddr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    let dst = String(cString: hostname)
                    if !dst.isEmpty {
                        vpnMap[name]?.ipv4.append("→ " + dst)
                    }
                }
            }
        }

        guard !vpnMap.isEmpty else { return items }

        items.append((NSLocalizedString("netdetail.label.status", comment: ""), NSLocalizedString("netdetail.value.vpn_active", comment: "")))

        for vpn in vpnMap.values.sorted(by: { $0.name < $1.name }) {
            items.append(("Interface", vpn.name))
            items.append(("Type", vpn.type))
            for ip in vpn.ipv4 {
                items.append(("Adresse IPv4", ip))
            }
            for ip in vpn.ipv6 {
                items.append(("Adresse IPv6", ip))
            }
        }

        return items
    }

    // MARK: - Network Interfaces

    struct InterfaceInfo {
        let name: String
        let family: String
        let address: String
        let netmask: String?
    }

    /// Énumère toutes les interfaces réseau via getifaddrs() et extrait les adresses IPv4/IPv6.
    private func getNetworkInterfaces() -> [InterfaceInfo] {
        var result: [InterfaceInfo] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return result }
        defer { freeifaddrs(ifaddr) }

        var ptr = Optional(firstAddr)
        while let addr = ptr {
            let name = String(cString: addr.pointee.ifa_name)
            let family = addr.pointee.ifa_addr.pointee.sa_family

            if family == UInt8(AF_INET) {
                let ipAddr = addr.pointee.ifa_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    var addrCopy = $0.pointee.sin_addr
                    inet_ntop(AF_INET, &addrCopy, &buffer, socklen_t(INET_ADDRSTRLEN))
                    return String(cString: buffer)
                }
                var netmask: String?
                if let mask = addr.pointee.ifa_netmask {
                    netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        var addrCopy = $0.pointee.sin_addr
                        inet_ntop(AF_INET, &addrCopy, &buffer, socklen_t(INET_ADDRSTRLEN))
                        return String(cString: buffer)
                    }
                }
                result.append(InterfaceInfo(name: name, family: "IPv4", address: ipAddr, netmask: netmask))
            } else if family == UInt8(AF_INET6) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr.pointee.ifa_addr, socklen_t(addr.pointee.ifa_addr.pointee.sa_len),
                           &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                let ipAddr = String(cString: hostname)
                result.append(InterfaceInfo(name: name, family: "IPv6", address: ipAddr, netmask: nil))
            }
            ptr = addr.pointee.ifa_next
        }
        return result
    }

    private func getInterfaceType(_ name: String) -> String? {
        if name.hasPrefix("en") { return "Ethernet / WiFi" }
        if name.hasPrefix("awdl") { return "Apple Wireless Direct Link" }
        if name.hasPrefix("bridge") { return "Bridge" }
        if name.hasPrefix("lo") { return "Loopback" }
        if name.hasPrefix("utun") { return "Tunnel (VPN)" }
        if name.hasPrefix("gif") { return "Tunnel GIF" }
        if name.hasPrefix("stf") { return "Tunnel 6to4" }
        if name.hasPrefix("llw") { return "Low Latency WLAN" }
        if name.hasPrefix("ap") { return "Access Point" }
        if name.hasPrefix("anpi") { return "Apple Network Protocol Interface" }
        return nil
    }

    /// Récupère les flags de l'interface (UP, RUNNING, BROADCAST…) via ioctl SIOCGIFFLAGS.
    private func getInterfaceFlags(_ name: String) -> String {
        let sock = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else { return "?" }
        defer { Darwin.close(sock) }

        var ifr = ifreq()
        _ = name.withCString { ptr in
            strncpy(&ifr.ifr_name.0, ptr, Int(IFNAMSIZ))
        }

        guard ioctl(sock, 0xc0206911, &ifr) >= 0 else { return "?" } // SIOCGIFFLAGS
        let flags = Int32(ifr.ifr_ifru.ifru_flags)

        var parts: [String] = []
        if flags & IFF_UP != 0 { parts.append("UP") }
        if flags & IFF_BROADCAST != 0 { parts.append("BROADCAST") }
        if flags & IFF_LOOPBACK != 0 { parts.append("LOOPBACK") }
        if flags & IFF_POINTOPOINT != 0 { parts.append("POINTOPOINT") }
        if flags & IFF_RUNNING != 0 { parts.append("RUNNING") }
        if flags & IFF_MULTICAST != 0 { parts.append("MULTICAST") }
        if flags & IFF_PROMISC != 0 { parts.append("PROMISC") }
        return parts.isEmpty ? "?" : parts.joined(separator: ",")
    }

    /// Récupère le MTU de l'interface via ioctl SIOCGIFMTU.
    private func getInterfaceMTU(_ name: String) -> Int? {
        let sock = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else { return nil }
        defer { Darwin.close(sock) }

        var ifr = ifreq()
        _ = name.withCString { ptr in
            strncpy(&ifr.ifr_name.0, ptr, Int(IFNAMSIZ))
        }

        guard ioctl(sock, 0xc0206933, &ifr) >= 0 else { return nil } // SIOCGIFMTU
        return Int(ifr.ifr_ifru.ifru_mtu)
    }

    /// Extrait l'adresse MAC (AF_LINK) d'une interface via getifaddrs() et sockaddr_dl.
    private func getMACAddress(_ name: String) -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = Optional(firstAddr)
        while let addr = ptr {
            let ifName = String(cString: addr.pointee.ifa_name)
            if ifName == name && addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                let sdl = addr.pointee.ifa_addr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { $0.pointee }
                let nlen = Int(sdl.sdl_nlen)
                let alen = Int(sdl.sdl_alen)
                guard alen == 6 else { ptr = addr.pointee.ifa_next; continue }

                var data = sdl.sdl_data
                let bytes = withUnsafePointer(to: &data) {
                    $0.withMemoryRebound(to: UInt8.self, capacity: nlen + alen) { ptr in
                        (0..<alen).map { ptr[nlen + $0] }
                    }
                }
                return bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
            }
            ptr = addr.pointee.ifa_next
        }
        return nil
    }

    // MARK: - WiFi

    private func getWiFiInfo() -> [(String, String)]? {
        guard let client = CWWiFiClient.shared().interface() else { return nil }

        // Verifier que le WiFi est connecte via wlanChannel() (fonctionne sans permissions de localisation)
        let channel = client.wlanChannel()
        let rssi = client.rssiValue()
        let isConnected = channel != nil || (rssi != 0 && rssi > -100)
        guard isConnected else { return nil }

        var items: [(String, String)] = []

        // Afficher le SSID ou "SSID privé" si non accessible (permissions de localisation sur macOS Sonoma+)
        if let ssid = client.ssid(), !ssid.isEmpty {
            items.append(("SSID", ssid))
        } else {
            items.append(("SSID", NSLocalizedString("wifi.status.private_ssid", comment: "")))
        }
        if let bssid = client.bssid() {
            items.append(("BSSID", bssid))
        }

        items.append(("RSSI", "\(rssi) dBm"))
        items.append((NSLocalizedString("netdetail.label.noise", comment: ""), "\(client.noiseMeasurement()) dBm"))

        if let channel = client.wlanChannel() {
            items.append((NSLocalizedString("netdetail.label.channel", comment: ""), "\(channel.channelNumber)"))
            let band: String
            switch channel.channelBand {
            case .band2GHz: band = "2.4 GHz"
            case .band5GHz: band = "5 GHz"
            case .band6GHz: band = "6 GHz"
            default: band = NSLocalizedString("netdetail.value.unknown", comment: "")
            }
            items.append((NSLocalizedString("netdetail.label.band", comment: ""), band))

            let width: String
            switch channel.channelWidth {
            case .width20MHz: width = "20 MHz"
            case .width40MHz: width = "40 MHz"
            case .width80MHz: width = "80 MHz"
            case .width160MHz: width = "160 MHz"
            default: width = NSLocalizedString("netdetail.value.unknown", comment: "")
            }
            items.append((NSLocalizedString("netdetail.label.channel_width", comment: ""), width))
        }

        if client.transmitRate() > 0 {
            items.append((NSLocalizedString("netdetail.label.tx_rate", comment: ""), String(format: "%.0f Mbps", client.transmitRate())))
        }

        let security = client.security()
        let secStr: String
        switch security {
        case .none: secStr = NSLocalizedString("netdetail.security.none", comment: "")
        case .WEP: secStr = "WEP"
        case .wpaPersonal: secStr = "WPA Personnel"
        case .wpaEnterprise: secStr = "WPA Enterprise"
        case .wpa2Personal: secStr = "WPA2 Personnel"
        case .wpa2Enterprise: secStr = "WPA2 Enterprise"
        case .wpa3Personal: secStr = "WPA3 Personnel"
        case .wpa3Enterprise: secStr = "WPA3 Enterprise"
        default: secStr = NSLocalizedString("netdetail.value.other", comment: "")
        }
        items.append((NSLocalizedString("netdetail.label.security", comment: ""), secStr))

        if let cc = client.countryCode() {
            items.append((NSLocalizedString("netdetail.label.country_code", comment: ""), cc))
        }

        items.append(("Mode", client.activePHYMode().description))

        return items.isEmpty ? nil : items
    }

    // MARK: - Routing

    /// Récupère la passerelle par défaut et l'interface de sortie via SCDynamicStore.
    private func getRoutingInfo() -> [(String, String)] {
        var items: [(String, String)] = []

        if let config = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any] {
            if let router = config["Router"] as? String {
                items.append((NSLocalizedString("netdetail.label.default_gateway", comment: ""), router))
            }
            if let iface = config["PrimaryInterface"] as? String {
                items.append((NSLocalizedString("netdetail.label.primary_interface", comment: ""), iface))
            }
        }

        if items.isEmpty {
            items.append((NSLocalizedString("netdetail.label.gateway", comment: ""), NSLocalizedString("netdetail.value.unavailable", comment: "")))
        }

        return items
    }

    // MARK: - DNS

    /// Lit la configuration DNS système (serveurs, domaine, domaines de recherche) via SCDynamicStore.
    private func getDNSInfo() -> [(String, String)] {
        var items: [(String, String)] = []

        if let config = SCDynamicStoreCopyValue(nil, "State:/Network/Global/DNS" as CFString) as? [String: Any] {
            if let servers = config["ServerAddresses"] as? [String] {
                for (i, server) in servers.enumerated() {
                    items.append(("Serveur DNS \(i + 1)", server))
                }
            }
            if let domain = config["DomainName"] as? String {
                items.append(("Domaine", domain))
            }
            if let searchDomains = config["SearchDomains"] as? [String] {
                items.append(("Domaines de recherche", searchDomains.joined(separator: ", ")))
            }
        }

        if items.isEmpty {
            items.append(("DNS", NSLocalizedString("netdetail.value.unavailable", comment: "")))
        }

        return items
    }

    // MARK: - Public IP

    /// Interroge ipify.org (IPv4) et api6.ipify.org (IPv6) pour obtenir les adresses IP publiques.
    private func getPublicIP() -> [(String, String)] {
        var items: [(String, String)] = []

        let semaphore = DispatchSemaphore(value: 0)
        if let url = URL(string: "https://api.ipify.org") {
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            URLSession.shared.dataTask(with: request) { data, _, _ in
                if let data = data, let ip = String(data: data, encoding: .utf8) {
                    items.append(("IPv4 publique", ip))
                }
                semaphore.signal()
            }.resume()
            _ = semaphore.wait(timeout: .now() + 5)
        }

        if let url = URL(string: "https://api6.ipify.org") {
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            URLSession.shared.dataTask(with: request) { data, _, _ in
                if let data = data, let ip = String(data: data, encoding: .utf8) {
                    items.append(("IPv6 publique", ip))
                }
                semaphore.signal()
            }.resume()
            _ = semaphore.wait(timeout: .now() + 5)
        }

        if items.isEmpty {
            items.append((NSLocalizedString("netdetail.label.public_ip", comment: ""), NSLocalizedString("netdetail.value.unavailable", comment: "")))
        }

        return items
    }

    // MARK: - Copier

    @objc private func copyAllInfo() {
        var text = NSLocalizedString("netdetail.report.header", comment: "") + "\n"
        text += String(repeating: "═", count: 50) + "\n\n"

        for section in sections {
            text += "[\(section.section)]\n"
            let maxLen = section.items.map { $0.0.count }.max() ?? 0
            for (label, value) in section.items {
                let padded = label.padding(toLength: maxLen + 3, withPad: " ", startingAt: 0)
                text += "  \(padded)\(value)\n"
            }
            text += "\n"
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    deinit {
        refreshTimer?.invalidate()
    }
}

extension CWPHYMode: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .mode11a: return "802.11a"
        case .mode11b: return "802.11b"
        case .mode11g: return "802.11g"
        case .mode11n: return "802.11n (Wi-Fi 4)"
        case .mode11ac: return "802.11ac (Wi-Fi 5)"
        case .mode11ax: return "802.11ax (Wi-Fi 6)"
        default: return NSLocalizedString("netdetail.value.unknown", comment: "")
        }
    }
}

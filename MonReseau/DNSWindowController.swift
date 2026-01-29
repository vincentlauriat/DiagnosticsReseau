import Cocoa
import SystemConfiguration
import dnssd

/// Fenetre affichant les informations DNS detaillees avec possibilite de faire des requetes.
class DNSWindowController: NSWindowController {

    private var scrollView: NSScrollView!
    private var textView: NSTextView!
    private var domainField: NSTextField!
    private var recordTypePopup: NSPopUpButton!
    private var lookupButton: NSButton!
    private var serverPopup: NSPopUpButton!
    private var latencyButton: NSButton!
    private var progressIndicator: NSProgressIndicator!

    private var isRunning = false

    // Serveurs DNS publics connus
    private let publicDNSServers: [(name: String, ipv4: String, ipv6: String?)] = [
        ("Serveur systeme", "", nil),
        ("Google", "8.8.8.8", "2001:4860:4860::8888"),
        ("Google secondaire", "8.8.4.4", "2001:4860:4860::8844"),
        ("Cloudflare", "1.1.1.1", "2606:4700:4700::1111"),
        ("Cloudflare secondaire", "1.0.0.1", "2606:4700:4700::1001"),
        ("Quad9", "9.9.9.9", "2620:fe::fe"),
        ("OpenDNS", "208.67.222.222", "2620:119:35::35"),
        ("AdGuard", "94.140.14.14", "2a10:50c0::ad1:ff"),
        ("FDN (France)", "80.67.169.12", "2001:910:800::12"),
    ]

    // Mapping type string -> DNS record type value
    private let recordTypeMap: [String: UInt16] = [
        "A": 1,       // kDNSServiceType_A
        "AAAA": 28,   // kDNSServiceType_AAAA
        "MX": 15,     // kDNSServiceType_MX
        "NS": 2,      // kDNSServiceType_NS
        "TXT": 16,    // kDNSServiceType_TXT
        "CNAME": 5,   // kDNSServiceType_CNAME
        "SOA": 6,     // kDNSServiceType_SOA
        "PTR": 12,    // kDNSServiceType_PTR
        "ANY": 255,   // kDNSServiceType_ANY
    ]

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mon Réseau — DNS"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 450)

        self.init(window: window)
        setupUI()
        showCurrentDNSConfig()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Toolbar avec les controles
        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(toolbar)

        // Champ domaine
        let domainLabel = NSTextField(labelWithString: "Domaine:")
        domainLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(domainLabel)

        domainField = NSTextField()
        domainField.translatesAutoresizingMaskIntoConstraints = false
        domainField.placeholderString = "exemple.com"
        domainField.target = self
        domainField.action = #selector(performLookup)
        toolbar.addSubview(domainField)

        // Type d'enregistrement
        let typeLabel = NSTextField(labelWithString: "Type:")
        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(typeLabel)

        recordTypePopup = NSPopUpButton()
        recordTypePopup.translatesAutoresizingMaskIntoConstraints = false
        recordTypePopup.addItems(withTitles: ["TOUS", "A", "AAAA", "MX", "NS", "TXT", "CNAME", "SOA", "PTR", "ANY"])
        toolbar.addSubview(recordTypePopup)

        // Serveur DNS
        let serverLabel = NSTextField(labelWithString: "Serveur:")
        serverLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(serverLabel)

        serverPopup = NSPopUpButton()
        serverPopup.translatesAutoresizingMaskIntoConstraints = false
        for server in publicDNSServers {
            if server.ipv4.isEmpty {
                serverPopup.addItem(withTitle: server.name)
            } else {
                serverPopup.addItem(withTitle: "\(server.name) (\(server.ipv4))")
            }
        }
        toolbar.addSubview(serverPopup)

        // Bouton lookup
        lookupButton = NSButton(title: "Resoudre", target: self, action: #selector(performLookup))
        lookupButton.translatesAutoresizingMaskIntoConstraints = false
        lookupButton.bezelStyle = .rounded
        lookupButton.keyEquivalent = "\r"
        toolbar.addSubview(lookupButton)

        // Seconde ligne de toolbar
        let toolbar2 = NSView()
        toolbar2.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(toolbar2)

        // Bouton test latence
        latencyButton = NSButton(title: "Tester latence DNS", target: self, action: #selector(testDNSLatency))
        latencyButton.translatesAutoresizingMaskIntoConstraints = false
        latencyButton.bezelStyle = .rounded
        toolbar2.addSubview(latencyButton)

        // Bouton config systeme
        let configButton = NSButton(title: "Config systeme", target: self, action: #selector(showCurrentDNSConfig))
        configButton.translatesAutoresizingMaskIntoConstraints = false
        configButton.bezelStyle = .rounded
        toolbar2.addSubview(configButton)

        // Bouton flush cache
        let flushButton = NSButton(title: "Vider cache DNS", target: self, action: #selector(flushDNSCache))
        flushButton.translatesAutoresizingMaskIntoConstraints = false
        flushButton.bezelStyle = .rounded
        toolbar2.addSubview(flushButton)

        // Indicateur de progression
        progressIndicator = NSProgressIndicator()
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.style = .spinning
        progressIndicator.isHidden = true
        toolbar2.addSubview(progressIndicator)

        // ScrollView avec textView
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.backgroundColor = .textBackgroundColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        scrollView.documentView = textView
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            // Toolbar 1
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            toolbar.heightAnchor.constraint(equalToConstant: 28),

            domainLabel.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            domainLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            domainField.leadingAnchor.constraint(equalTo: domainLabel.trailingAnchor, constant: 6),
            domainField.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            domainField.widthAnchor.constraint(equalToConstant: 150),

            typeLabel.leadingAnchor.constraint(equalTo: domainField.trailingAnchor, constant: 12),
            typeLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            recordTypePopup.leadingAnchor.constraint(equalTo: typeLabel.trailingAnchor, constant: 6),
            recordTypePopup.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            recordTypePopup.widthAnchor.constraint(equalToConstant: 80),

            serverLabel.leadingAnchor.constraint(equalTo: recordTypePopup.trailingAnchor, constant: 12),
            serverLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            serverPopup.leadingAnchor.constraint(equalTo: serverLabel.trailingAnchor, constant: 6),
            serverPopup.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            serverPopup.widthAnchor.constraint(equalToConstant: 140),

            lookupButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            lookupButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            // Toolbar 2
            toolbar2.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            toolbar2.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            toolbar2.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 12),
            toolbar2.heightAnchor.constraint(equalToConstant: 28),

            latencyButton.leadingAnchor.constraint(equalTo: toolbar2.leadingAnchor),
            latencyButton.centerYAnchor.constraint(equalTo: toolbar2.centerYAnchor),

            configButton.leadingAnchor.constraint(equalTo: latencyButton.trailingAnchor, constant: 8),
            configButton.centerYAnchor.constraint(equalTo: toolbar2.centerYAnchor),

            flushButton.leadingAnchor.constraint(equalTo: configButton.trailingAnchor, constant: 8),
            flushButton.centerYAnchor.constraint(equalTo: toolbar2.centerYAnchor),

            progressIndicator.trailingAnchor.constraint(equalTo: toolbar2.trailingAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: toolbar2.centerYAnchor),

            // ScrollView
            scrollView.topAnchor.constraint(equalTo: toolbar2.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    // MARK: - Actions

    @objc private func showCurrentDNSConfig() {
        var output = "═══════════════════════════════════════════════════════════════════\n"
        output += "                    CONFIGURATION DNS SYSTEME\n"
        output += "═══════════════════════════════════════════════════════════════════\n\n"

        if let config = SCDynamicStoreCopyValue(nil, "State:/Network/Global/DNS" as CFString) as? [String: Any] {
            if let servers = config["ServerAddresses"] as? [String] {
                output += "SERVEURS DNS CONFIGURES:\n"
                for (i, server) in servers.enumerated() {
                    let serverInfo = identifyDNSServer(server)
                    output += "  \(i + 1). \(server)"
                    if let info = serverInfo {
                        output += " (\(info))"
                    }
                    output += "\n"
                }
                output += "\n"
            }

            if let domain = config["DomainName"] as? String {
                output += "DOMAINE:\n  \(domain)\n\n"
            }

            if let searchDomains = config["SearchDomains"] as? [String] {
                output += "DOMAINES DE RECHERCHE:\n"
                for domain in searchDomains {
                    output += "  - \(domain)\n"
                }
                output += "\n"
            }

            if let options = config["Options"] as? String {
                output += "OPTIONS:\n  \(options)\n\n"
            }
        } else {
            output += "Impossible de recuperer la configuration DNS.\n\n"
        }

        // Liste des serveurs DNS connus
        output += "───────────────────────────────────────────────────────────────────\n"
        output += "SERVEURS DNS PUBLICS DISPONIBLES:\n"
        output += "───────────────────────────────────────────────────────────────────\n"
        for server in publicDNSServers where !server.ipv4.isEmpty {
            output += "  \(server.name.padding(toLength: 22, withPad: " ", startingAt: 0))"
            output += "IPv4: \(server.ipv4)"
            if let ipv6 = server.ipv6 {
                output += "  IPv6: \(ipv6)"
            }
            output += "\n"
        }

        appendText(output)
    }

    private func identifyDNSServer(_ ip: String) -> String? {
        for server in publicDNSServers {
            if server.ipv4 == ip || server.ipv6 == ip {
                return server.name
            }
        }
        switch ip {
        case "192.168.1.1", "192.168.0.1", "192.168.1.254":
            return "Routeur local"
        default:
            if ip.hasPrefix("192.168.") || ip.hasPrefix("10.") || ip.hasPrefix("172.") {
                return "Reseau local"
            }
            return nil
        }
    }

    @objc private func performLookup() {
        let domain = domainField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !domain.isEmpty else {
            appendText("\n  Veuillez entrer un nom de domaine.\n")
            return
        }

        guard !isRunning else { return }

        let recordType = recordTypePopup.titleOfSelectedItem ?? "A"
        let serverIndex = serverPopup.indexOfSelectedItem
        let server = serverIndex > 0 ? publicDNSServers[serverIndex].ipv4 : nil

        startProgress()

        if recordType == "TOUS" {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.executeAllDNSLookups(domain: domain, server: server)
            }
        } else {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.executeDNSLookup(domain: domain, recordType: recordType, server: server)
                DispatchQueue.main.async { self?.stopProgress() }
            }
        }
    }

    private let allRecordTypes = ["A", "AAAA", "MX", "NS", "TXT", "CNAME", "SOA"]

    private func executeAllDNSLookups(domain: String, server: String?) {
        let serverName = server ?? "Systeme"
        var output = "\n═══════════════════════════════════════════════════════════════════\n"
        output += "REQUETE DNS COMPLETE pour \(domain)\n"
        output += "Serveur: \(serverName)\n"
        output += "═══════════════════════════════════════════════════════════════════\n"

        let totalStart = CFAbsoluteTimeGetCurrent()

        for recordType in allRecordTypes {
            output += "\n── \(recordType) ─────────────────────────────────────────────────────\n"

            let records = nativeDNSQuery(domain: domain, recordType: recordType, server: server)

            if records.isEmpty {
                output += "  (aucun enregistrement)\n"
            } else {
                for record in records {
                    output += "  \(record.type.padding(toLength: 6, withPad: " ", startingAt: 0))"
                    output += "\(record.name.padding(toLength: 30, withPad: " ", startingAt: 0))"
                    output += "TTL: \(String(record.ttl).padding(toLength: 8, withPad: " ", startingAt: 0))"
                    output += "\(record.value)\n"
                }
            }
        }

        let totalElapsed = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000
        output += "\n───────────────────────────────────────────────────────────────────\n"
        output += "Temps total: \(String(format: "%.1f", totalElapsed)) ms\n"

        DispatchQueue.main.async { [weak self] in
            self?.appendText(output)
            self?.stopProgress()
        }
    }

    private func executeDNSLookup(domain: String, recordType: String, server: String?) {
        var output = "\n═══════════════════════════════════════════════════════════════════\n"
        output += "REQUETE DNS: \(recordType) pour \(domain)\n"
        if let server = server {
            output += "Serveur: \(server)\n"
        } else {
            output += "Serveur: Systeme\n"
        }
        output += "═══════════════════════════════════════════════════════════════════\n\n"

        let startTime = CFAbsoluteTimeGetCurrent()

        let records = nativeDNSQuery(domain: domain, recordType: recordType, server: server)

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        if records.isEmpty {
            output += "Aucun enregistrement \(recordType) trouve.\n"
        } else {
            for record in records {
                output += "  \(record.type.padding(toLength: 6, withPad: " ", startingAt: 0))"
                output += "\(record.name.padding(toLength: 30, withPad: " ", startingAt: 0))"
                output += "TTL: \(String(record.ttl).padding(toLength: 8, withPad: " ", startingAt: 0))"
                output += "\(record.value)\n"
            }
        }

        output += "\nTemps de requete: \(String(format: "%.1f", elapsed)) ms\n"

        DispatchQueue.main.async { [weak self] in
            self?.appendText(output)
        }
    }

    // MARK: - Native DNS Resolution

    struct DNSRecord {
        let name: String
        let type: String
        let ttl: UInt32
        let value: String
    }

    /// Effectue une requete DNS native via DNSServiceQueryRecord.
    private func nativeDNSQuery(domain: String, recordType: String, server: String?) -> [DNSRecord] {
        guard let rrType = recordTypeMap[recordType] else { return [] }

        // Si un serveur specifique est demande, utiliser getaddrinfo comme fallback simple
        // car DNSServiceQueryRecord utilise toujours le resolveur systeme
        if let server = server {
            return dnsQueryViaUDP(domain: domain, rrType: rrType, typeName: recordType, server: server)
        }

        var sdRef: DNSServiceRef?
        var records: [DNSRecord] = []

        // Context pour le callback
        class QueryContext {
            var records: [DNSRecord] = []
            var domain: String
            var typeName: String
            init(domain: String, typeName: String) {
                self.domain = domain
                self.typeName = typeName
            }
        }

        let context = QueryContext(domain: domain, typeName: recordType)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()

        let callback: DNSServiceQueryRecordReply = { _, _, _, errorCode, fullname, rrtype, _, rdlen, rdata, ttl, context in
            guard let context = context else { return }
            let ctx = Unmanaged<QueryContext>.fromOpaque(context).takeUnretainedValue()

            guard errorCode == kDNSServiceErr_NoError, let rdata = rdata, rdlen > 0 else { return }

            let name = fullname.map { String(cString: $0) } ?? ctx.domain
            let data = Data(bytes: rdata, count: Int(rdlen))

            let value: String
            switch rrtype {
            case 1: // A
                if data.count == 4 {
                    value = data.map { String($0) }.joined(separator: ".")
                } else {
                    value = "(donnees invalides)"
                }
            case 28: // AAAA
                if data.count == 16 {
                    var parts: [String] = []
                    for i in stride(from: 0, to: 16, by: 2) {
                        let word = UInt16(data[i]) << 8 | UInt16(data[i + 1])
                        parts.append(String(format: "%x", word))
                    }
                    value = parts.joined(separator: ":")
                } else {
                    value = "(donnees invalides)"
                }
            case 15: // MX
                if data.count >= 3 {
                    let priority = UInt16(data[0]) << 8 | UInt16(data[1])
                    let exchange = DNSWindowController.parseDNSName(from: data, offset: 2)
                    value = "\(priority) \(exchange)"
                } else {
                    value = "(donnees invalides)"
                }
            case 2, 5, 12: // NS, CNAME, PTR
                value = DNSWindowController.parseDNSName(from: data, offset: 0)
            case 16: // TXT
                if data.count > 0 {
                    var texts: [String] = []
                    var offset = 0
                    while offset < data.count {
                        let len = Int(data[offset])
                        offset += 1
                        if offset + len <= data.count {
                            let str = String(data: data[offset..<offset + len], encoding: .utf8) ?? "(binaire)"
                            texts.append(str)
                            offset += len
                        } else {
                            break
                        }
                    }
                    value = "\"" + texts.joined(separator: "\" \"") + "\""
                } else {
                    value = "(vide)"
                }
            case 6: // SOA
                value = DNSWindowController.parseSOA(from: data)
            default:
                value = "(\(rdlen) octets)"
            }

            let typeName: String
            switch rrtype {
            case 1: typeName = "A"
            case 2: typeName = "NS"
            case 5: typeName = "CNAME"
            case 6: typeName = "SOA"
            case 12: typeName = "PTR"
            case 15: typeName = "MX"
            case 16: typeName = "TXT"
            case 28: typeName = "AAAA"
            default: typeName = "TYPE\(rrtype)"
            }

            ctx.records.append(DNSRecord(name: name, type: typeName, ttl: ttl, value: value))
        }

        let err = DNSServiceQueryRecord(&sdRef, kDNSServiceFlagsReturnIntermediates, 0,
                                         domain, rrType, UInt16(kDNSServiceClass_IN),
                                         callback, contextPtr)

        if err == kDNSServiceErr_NoError, let sdRef = sdRef {
            let fd = DNSServiceRefSockFD(sdRef)
            var readSet = fd_set()
            __darwin_fd_zero(&readSet)

            // Attendre les reponses pendant max 3 secondes
            let deadline = CFAbsoluteTimeGetCurrent() + 3.0
            var gotResult = false
            while CFAbsoluteTimeGetCurrent() < deadline {
                __darwin_fd_zero(&readSet)
                __darwin_fd_set(fd, &readSet)
                var timeout = timeval(tv_sec: 0, tv_usec: 200_000) // 200ms
                let result = select(fd + 1, &readSet, nil, nil, &timeout)
                if result > 0 {
                    DNSServiceProcessResult(sdRef)
                    gotResult = true
                    // Continuer un peu pour collecter plus de reponses
                    if !context.records.isEmpty {
                        // Attendre encore un peu pour les reponses supplementaires
                        usleep(100_000) // 100ms
                        __darwin_fd_zero(&readSet)
                        __darwin_fd_set(fd, &readSet)
                        var shortTimeout = timeval(tv_sec: 0, tv_usec: 100_000)
                        let r2 = select(fd + 1, &readSet, nil, nil, &shortTimeout)
                        if r2 > 0 {
                            DNSServiceProcessResult(sdRef)
                        }
                        break
                    }
                } else if gotResult {
                    break
                }
            }

            DNSServiceRefDeallocate(sdRef)
        }

        records = context.records
        Unmanaged<QueryContext>.fromOpaque(contextPtr).release()

        return records
    }

    /// Requete DNS directe via UDP vers un serveur specifique.
    private func dnsQueryViaUDP(domain: String, rrType: UInt16, typeName: String, server: String) -> [DNSRecord] {
        // Construire un paquet DNS
        let transactionID: UInt16 = UInt16.random(in: 1...UInt16.max)
        var packet = Data()

        // Header
        packet.append(contentsOf: withUnsafeBytes(of: transactionID.bigEndian) { Array($0) })
        packet.append(contentsOf: [0x01, 0x00]) // Flags: standard query, recursion desired
        packet.append(contentsOf: [0x00, 0x01]) // QDCOUNT: 1
        packet.append(contentsOf: [0x00, 0x00]) // ANCOUNT: 0
        packet.append(contentsOf: [0x00, 0x00]) // NSCOUNT: 0
        packet.append(contentsOf: [0x00, 0x00]) // ARCOUNT: 0

        // Question: domain name
        for label in domain.split(separator: ".") {
            packet.append(UInt8(label.count))
            packet.append(contentsOf: label.utf8)
        }
        packet.append(0) // Terminateur

        // Type et class
        packet.append(contentsOf: withUnsafeBytes(of: rrType.bigEndian) { Array($0) })
        packet.append(contentsOf: [0x00, 0x01]) // IN class

        // Envoyer via UDP
        let sock = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return [] }
        defer { Darwin.close(sock) }

        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(53).bigEndian
        addr.sin_addr.s_addr = inet_addr(server)

        let sent = packet.withUnsafeBytes { ptr in
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    sendto(sock, ptr.baseAddress, ptr.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent > 0 else { return [] }

        // Recevoir la reponse
        var recvBuf = [UInt8](repeating: 0, count: 4096)
        let recvLen = recv(sock, &recvBuf, recvBuf.count, 0)
        guard recvLen > 12 else { return [] }

        let response = Data(recvBuf[0..<recvLen])
        return parseDNSResponse(response, domain: domain, queryType: typeName)
    }

    /// Parse une reponse DNS brute.
    private func parseDNSResponse(_ data: Data, domain: String, queryType: String) -> [DNSRecord] {
        guard data.count > 12 else { return [] }

        let anCount = Int(UInt16(data[6]) << 8 | UInt16(data[7]))
        guard anCount > 0 else { return [] }

        // Sauter le header (12 octets) et la section question
        var offset = 12

        // Sauter la question
        while offset < data.count && data[offset] != 0 {
            let len = Int(data[offset])
            if len & 0xC0 == 0xC0 {
                offset += 2
                break
            }
            offset += len + 1
        }
        if offset < data.count && data[offset] == 0 { offset += 1 }
        offset += 4 // type + class de la question

        var records: [DNSRecord] = []

        for _ in 0..<anCount {
            guard offset < data.count else { break }

            // Nom
            let (name, newOffset) = readDNSName(from: data, offset: offset)
            offset = newOffset

            guard offset + 10 <= data.count else { break }

            let rrType = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            offset += 2
            // class
            offset += 2
            let ttl = UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16 |
                       UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
            offset += 4
            let rdLen = Int(UInt16(data[offset]) << 8 | UInt16(data[offset + 1]))
            offset += 2

            guard offset + rdLen <= data.count else { break }

            let rdata = data[offset..<offset + rdLen]
            offset += rdLen

            let value: String
            let typeName: String

            switch rrType {
            case 1: // A
                typeName = "A"
                if rdata.count == 4 {
                    value = rdata.map { String($0) }.joined(separator: ".")
                } else { value = "?" }
            case 28: // AAAA
                typeName = "AAAA"
                if rdata.count == 16 {
                    var parts: [String] = []
                    let rdataArray = Array(rdata)
                    for i in stride(from: 0, to: 16, by: 2) {
                        let word = UInt16(rdataArray[i]) << 8 | UInt16(rdataArray[i + 1])
                        parts.append(String(format: "%x", word))
                    }
                    value = parts.joined(separator: ":")
                } else { value = "?" }
            case 15: // MX
                typeName = "MX"
                if rdata.count >= 3 {
                    let rdataArray = Array(rdata)
                    let priority = UInt16(rdataArray[0]) << 8 | UInt16(rdataArray[1])
                    let (exchange, _) = readDNSName(from: data, offset: offset - rdLen + 2)
                    value = "\(priority) \(exchange)"
                } else { value = "?" }
            case 2:
                typeName = "NS"
                let (ns, _) = readDNSName(from: data, offset: offset - rdLen)
                value = ns
            case 5:
                typeName = "CNAME"
                let (cname, _) = readDNSName(from: data, offset: offset - rdLen)
                value = cname
            case 12:
                typeName = "PTR"
                let (ptr, _) = readDNSName(from: data, offset: offset - rdLen)
                value = ptr
            case 16: // TXT
                typeName = "TXT"
                let rdataArray = Array(rdata)
                var texts: [String] = []
                var off = 0
                while off < rdataArray.count {
                    let len = Int(rdataArray[off])
                    off += 1
                    if off + len <= rdataArray.count {
                        let str = String(bytes: rdataArray[off..<off + len], encoding: .utf8) ?? "(binaire)"
                        texts.append(str)
                        off += len
                    } else { break }
                }
                value = "\"" + texts.joined(separator: "\" \"") + "\""
            case 6: // SOA
                typeName = "SOA"
                let (mname, off1) = readDNSName(from: data, offset: offset - rdLen)
                let (rname, _) = readDNSName(from: data, offset: off1)
                value = "\(mname) \(rname)"
            default:
                typeName = "TYPE\(rrType)"
                value = "(\(rdLen) octets)"
            }

            records.append(DNSRecord(name: name.isEmpty ? domain : name, type: typeName, ttl: ttl, value: value))
        }

        return records
    }

    /// Lit un nom DNS compresse depuis un buffer.
    private func readDNSName(from data: Data, offset: Int) -> (String, Int) {
        var labels: [String] = []
        var pos = offset
        var jumped = false
        var returnOffset = offset

        while pos < data.count {
            let len = Int(data[pos])
            if len == 0 {
                pos += 1
                if !jumped { returnOffset = pos }
                break
            }
            if len & 0xC0 == 0xC0 {
                // Pointeur de compression
                guard pos + 1 < data.count else { break }
                let pointer = Int(len & 0x3F) << 8 | Int(data[pos + 1])
                if !jumped { returnOffset = pos + 2 }
                pos = pointer
                jumped = true
                continue
            }
            pos += 1
            guard pos + len <= data.count else { break }
            let label = String(bytes: data[pos..<pos + len], encoding: .utf8) ?? ""
            labels.append(label)
            pos += len
        }

        if !jumped { returnOffset = pos }
        return (labels.joined(separator: "."), returnOffset)
    }

    /// Parse un nom DNS depuis un Data avec offset (pour le callback dnssd).
    static func parseDNSName(from data: Data, offset: Int) -> String {
        var labels: [String] = []
        var pos = offset
        while pos < data.count {
            let len = Int(data[pos])
            if len == 0 { break }
            pos += 1
            guard pos + len <= data.count else { break }
            let label = String(data: data[pos..<pos + len], encoding: .utf8) ?? ""
            labels.append(label)
            pos += len
        }
        return labels.joined(separator: ".")
    }

    /// Parse un enregistrement SOA depuis un Data.
    static func parseSOA(from data: Data) -> String {
        var labels: [String] = []
        var pos = 0
        // MNAME
        while pos < data.count {
            let len = Int(data[pos])
            if len == 0 { pos += 1; break }
            pos += 1
            guard pos + len <= data.count else { break }
            let label = String(data: data[pos..<pos + len], encoding: .utf8) ?? ""
            labels.append(label)
            pos += len
        }
        let mname = labels.joined(separator: ".")

        labels = []
        // RNAME
        while pos < data.count {
            let len = Int(data[pos])
            if len == 0 { pos += 1; break }
            pos += 1
            guard pos + len <= data.count else { break }
            let label = String(data: data[pos..<pos + len], encoding: .utf8) ?? ""
            labels.append(label)
            pos += len
        }
        let rname = labels.joined(separator: ".")

        return "\(mname) \(rname)"
    }

    // MARK: - DNS Latency Test

    @objc private func testDNSLatency() {
        guard !isRunning else { return }

        startProgress()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.executeDNSLatencyTest()
        }
    }

    private func executeDNSLatencyTest() {
        var output = "\n═══════════════════════════════════════════════════════════════════\n"
        output += "                    TEST DE LATENCE DNS\n"
        output += "═══════════════════════════════════════════════════════════════════\n\n"
        output += "Resolution de 'google.com' sur chaque serveur (3 essais):\n\n"

        var results: [(name: String, ip: String, latency: Double?)] = []

        // Tester le serveur systeme
        let sysLatency = measureDNSLatency(server: nil, domain: "google.com", attempts: 3)
        results.append(("Serveur systeme", "-", sysLatency))

        // Tester les serveurs publics
        for server in publicDNSServers where !server.ipv4.isEmpty {
            let latency = measureDNSLatency(server: server.ipv4, domain: "google.com", attempts: 3)
            results.append((server.name, server.ipv4, latency))
        }

        // Trier par latence
        results.sort { ($0.latency ?? 9999) < ($1.latency ?? 9999) }

        // Afficher les resultats
        output += "  Serveur                     IP                Latence\n"
        output += "  ─────────────────────────────────────────────────────────\n"

        for (i, result) in results.enumerated() {
            let medal = i == 0 ? "  1." : (i == 1 ? "  2." : (i == 2 ? "  3." : "  \(i + 1)."))
            let name = result.name.padding(toLength: 22, withPad: " ", startingAt: 0)
            let ip = result.ip.padding(toLength: 16, withPad: " ", startingAt: 0)
            let latency: String
            if let lat = result.latency {
                latency = String(format: "%.1f ms", lat)
            } else {
                latency = "Erreur"
            }
            output += "\(medal) \(name) \(ip) \(latency)\n"
        }

        output += "\n"

        DispatchQueue.main.async { [weak self] in
            self?.appendText(output)
            self?.stopProgress()
        }
    }

    private func measureDNSLatency(server: String?, domain: String, attempts: Int) -> Double? {
        var times: [Double] = []

        for _ in 0..<attempts {
            let startTime = CFAbsoluteTimeGetCurrent()
            let records: [DNSRecord]
            if let server = server {
                records = dnsQueryViaUDP(domain: domain, rrType: 1, typeName: "A", server: server)
            } else {
                records = nativeDNSQuery(domain: domain, recordType: "A", server: nil)
            }
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

            if !records.isEmpty {
                times.append(elapsed)
            }
        }

        guard !times.isEmpty else { return nil }
        return times.reduce(0, +) / Double(times.count)
    }

    @objc private func flushDNSCache() {
        var output = "\n═══════════════════════════════════════════════════════════════════\n"
        output += "                    VIDER LE CACHE DNS\n"
        output += "═══════════════════════════════════════════════════════════════════\n\n"

        output += "Pour vider le cache DNS sur macOS, executez cette commande dans le Terminal:\n\n"
        output += "  sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder\n\n"
        output += "(Droits administrateur requis)\n\n"

        // Copier la commande dans le presse-papiers
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder", forType: .string)

        output += "Commande copiee dans le presse-papiers.\n"

        appendText(output)
    }

    // MARK: - Helpers

    private func appendText(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let textView = self?.textView else { return }
            let attributed = NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ])
            textView.textStorage?.append(attributed)
            textView.scrollToEndOfDocument(nil)
        }
    }

    private func startProgress() {
        isRunning = true
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        lookupButton.isEnabled = false
        latencyButton.isEnabled = false
    }

    private func stopProgress() {
        isRunning = false
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        lookupButton.isEnabled = true
        latencyButton.isEnabled = true
    }
}

// fd_set helpers
private func __darwin_fd_zero(_ set: inout fd_set) {
    set = fd_set()
}

private func __darwin_fd_set(_ fd: Int32, _ set: inout fd_set) {
    let intOffset = Int(fd) / 32
    let bitOffset = Int(fd) % 32
    withUnsafeMutablePointer(to: &set) { ptr in
        let raw = UnsafeMutableRawPointer(ptr)
        let intArray = raw.assumingMemoryBound(to: Int32.self)
        intArray[intOffset] |= Int32(1 << bitOffset)
    }
}

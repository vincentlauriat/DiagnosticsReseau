// WhoisWindowController.swift
// Mon Réseau
//
// Fenêtre Whois : interroge les serveurs WHOIS via NWConnection (TCP port 43).
// Détecte automatiquement le bon serveur WHOIS selon le TLD.
// Supporte les domaines et les adresses IP.

import Cocoa
import Network

class WhoisWindowController: NSWindowController {

    private var targetTextField: NSTextField!
    private var queryButton: NSButton!
    private var progressIndicator: NSProgressIndicator!
    private var resultTextView: NSTextView!
    private var statusLabel: NSTextField!
    private var copyButton: NSButton!
    private var favoritesPopup: NSPopUpButton!
    private var isQuerying = false

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 550),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("whois.title", comment: "")
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 400)

        self.init(window: window)
        setupUI()
        window.initialFirstResponder = targetTextField
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        // Title
        let titleLabel = NSTextField(labelWithString: NSLocalizedString("whois.heading", comment: ""))
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        // Input row
        let inputStack = NSStackView()
        inputStack.orientation = .horizontal
        inputStack.spacing = 10
        inputStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(inputStack)

        targetTextField = NSTextField()
        targetTextField.placeholderString = "example.com / 8.8.8.8"
        targetTextField.target = self
        targetTextField.action = #selector(performQuery)
        targetTextField.translatesAutoresizingMaskIntoConstraints = false
        targetTextField.widthAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
        inputStack.addArrangedSubview(targetTextField)

        queryButton = NSButton(title: NSLocalizedString("whois.button.query", comment: ""), target: self, action: #selector(performQuery))
        queryButton.bezelStyle = .rounded
        inputStack.addArrangedSubview(queryButton)

        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isHidden = true
        inputStack.addArrangedSubview(progressIndicator)

        copyButton = NSButton(title: NSLocalizedString("whois.button.copy", comment: ""), target: self, action: #selector(copyResult))
        copyButton.bezelStyle = .rounded
        inputStack.addArrangedSubview(copyButton)

        let addFavButton = NSButton(title: "★", target: self, action: #selector(toggleFavorite))
        addFavButton.bezelStyle = .rounded
        addFavButton.toolTip = NSLocalizedString("favorites.add", comment: "")
        inputStack.addArrangedSubview(addFavButton)

        favoritesPopup = NSPopUpButton()
        favoritesPopup.bezelStyle = .rounded
        favoritesPopup.target = self
        favoritesPopup.action = #selector(loadFavorite)
        inputStack.addArrangedSubview(favoritesPopup)
        refreshFavoritesPopup()

        // Status
        statusLabel = NSTextField(labelWithString: NSLocalizedString("whois.status.ready", comment: ""))
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusLabel)

        // Result text view
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder
        contentView.addSubview(scrollView)

        resultTextView = NSTextView()
        resultTextView.isEditable = false
        resultTextView.isSelectable = true
        resultTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        resultTextView.textColor = .labelColor
        resultTextView.backgroundColor = .textBackgroundColor
        resultTextView.autoresizingMask = [.width]
        resultTextView.isVerticallyResizable = true
        resultTextView.isHorizontallyResizable = false
        resultTextView.textContainer?.widthTracksTextView = true
        resultTextView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = resultTextView

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            inputStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            inputStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            inputStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),

            statusLabel.topAnchor.constraint(equalTo: inputStack.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    // MARK: - Actions

    @objc private func performQuery() {
        let target = targetTextField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty, !isQuerying else { return }

        isQuerying = true
        queryButton.isEnabled = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        resultTextView.string = ""
        statusLabel.stringValue = String(format: NSLocalizedString("whois.status.querying", comment: ""), target)

        let server = whoisServer(for: target)
        let query = whoisQuery(for: target, server: server)

        statusLabel.stringValue = String(format: NSLocalizedString("whois.status.connecting", comment: ""), server)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.executeWhoisQuery(server: server, query: query, target: target)
        }
    }

    @objc private func copyResult() {
        let text = resultTextView.string
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Whois Server Resolution

    /// Détermine le serveur WHOIS approprié selon le TLD ou le type d'adresse.
    private func whoisServer(for target: String) -> String {
        // IP address → ARIN (will redirect if needed)
        if target.contains(":") || target.allSatisfy({ $0.isNumber || $0 == "." }) {
            return "whois.arin.net"
        }

        let components = target.lowercased().split(separator: ".")
        guard let tld = components.last else { return "whois.iana.org" }

        let tldServers: [String: String] = [
            "com": "whois.verisign-grs.com",
            "net": "whois.verisign-grs.com",
            "org": "whois.pir.org",
            "info": "whois.afilias.net",
            "io": "whois.nic.io",
            "dev": "whois.nic.google",
            "app": "whois.nic.google",
            "fr": "whois.nic.fr",
            "de": "whois.denic.de",
            "uk": "whois.nic.uk",
            "eu": "whois.eu",
            "co": "whois.nic.co",
            "me": "whois.nic.me",
            "tv": "whois.nic.tv",
            "cc": "ccwhois.verisign-grs.com",
            "be": "whois.dns.be",
            "nl": "whois.domain-registry.nl",
            "ch": "whois.nic.ch",
            "it": "whois.nic.it",
            "es": "whois.nic.es",
            "us": "whois.nic.us",
            "ca": "whois.cira.ca",
            "au": "whois.auda.org.au",
            "jp": "whois.jprs.jp",
            "cn": "whois.cnnic.cn",
            "ru": "whois.tcinet.ru",
            "br": "whois.registro.br",
        ]

        return tldServers[String(tld)] ?? "whois.iana.org"
    }

    /// Construit la requête WHOIS (certains serveurs nécessitent un préfixe).
    private func whoisQuery(for target: String, server: String) -> String {
        if server == "whois.verisign-grs.com" {
            return "=\(target)\r\n"
        }
        if server == "whois.denic.de" {
            return "-T dn,ace \(target)\r\n"
        }
        if server == "whois.jprs.jp" {
            return "\(target)/e\r\n"
        }
        return "\(target)\r\n"
    }

    // MARK: - Network Query (NWConnection)

    private func executeWhoisQuery(server: String, query: String, target: String) {
        let host = NWEndpoint.Host(server)
        let port = NWEndpoint.Port(integerLiteral: 43)
        let connection = NWConnection(host: host, port: port, using: .tcp)

        let responseBuffer = DataWrapper(data: Data())
        let timeout = DispatchTime.now() + .seconds(15)

        let semaphore = DispatchSemaphore(value: 0)
        var completed = false

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                let data = query.data(using: .utf8)!
                connection.send(content: data, completion: .contentProcessed({ error in
                    if let error = error {
                        DispatchQueue.main.async {
                            self?.showError(String(format: NSLocalizedString("whois.error.send", comment: ""), error.localizedDescription))
                        }
                        completed = true
                        semaphore.signal()
                        return
                    }
                    self?.receiveData(connection: connection, buffer: responseBuffer) {
                        completed = true
                        semaphore.signal()
                    }
                }))

            case .failed(let error):
                DispatchQueue.main.async {
                    self?.showError(String(format: NSLocalizedString("whois.error.connection", comment: ""), error.localizedDescription))
                }
                completed = true
                semaphore.signal()

            default:
                break
            }
        }

        connection.start(queue: DispatchQueue.global(qos: .userInitiated))

        let result = semaphore.wait(timeout: timeout)
        connection.cancel()

        if result == .timedOut && !completed {
            DispatchQueue.main.async { [weak self] in
                self?.showError(NSLocalizedString("whois.error.timeout", comment: ""))
            }
            return
        }

        let responseData = responseBuffer.data
        let responseString: String
        if let utf8 = String(data: responseData, encoding: .utf8) {
            responseString = utf8
        } else if let latin1 = String(data: responseData, encoding: .isoLatin1) {
            responseString = latin1
        } else {
            responseString = String(data: responseData, encoding: .ascii) ?? ""
        }

        let referralServer = extractReferralServer(from: responseString)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let referral = referralServer, referral != server {
                self.statusLabel.stringValue = String(format: NSLocalizedString("whois.status.redirect", comment: ""), referral)
                let newQuery = self.whoisQuery(for: target, server: referral)
                DispatchQueue.global(qos: .userInitiated).async {
                    self.executeWhoisQuery(server: referral, query: newQuery, target: target)
                }
            } else {
                self.finishQuery(response: responseString, server: server)
            }
        }
    }

    /// Lecture récursive des données depuis la connexion.
    private func receiveData(connection: NWConnection, buffer: DataWrapper, completion: @escaping () -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data {
                buffer.data.append(data)
            }
            if isComplete || error != nil {
                completion()
            } else {
                self?.receiveData(connection: connection, buffer: buffer, completion: completion)
            }
        }
    }

    /// Extrait un serveur de redirection depuis la réponse WHOIS.
    private func extractReferralServer(from response: String) -> String? {
        let patterns = [
            "ReferralServer: whois://",
            "ReferralServer:  whois://",
            "refer:        ",
            "refer: ",
            "Registrar WHOIS Server: ",
        ]
        for line in response.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for pattern in patterns {
                if trimmed.hasPrefix(pattern) {
                    var server = String(trimmed.dropFirst(pattern.count))
                    server = server.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Retirer le port si présent
                    if let colonIndex = server.firstIndex(of: ":") {
                        server = String(server[..<colonIndex])
                    }
                    if !server.isEmpty { return server }
                }
            }
        }
        return nil
    }

    // MARK: - UI Updates

    private func finishQuery(response: String, server: String) {
        isQuerying = false
        queryButton.isEnabled = true
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true

        if response.isEmpty {
            statusLabel.stringValue = NSLocalizedString("whois.status.empty", comment: "")
            resultTextView.string = NSLocalizedString("whois.result.empty", comment: "")
        } else {
            let lineCount = response.components(separatedBy: "\n").count
            statusLabel.stringValue = String(format: NSLocalizedString("whois.status.done", comment: ""), server, lineCount)
            resultTextView.textStorage?.setAttributedString(Self.colorize(response))
            resultTextView.scrollToBeginningOfDocument(nil)
        }
    }

    private static let ipv4Regex = try! NSRegularExpression(pattern: "\\b\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\b")

    private static func colorize(_ text: String) -> NSAttributedString {
        let baseFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let boldFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        let result = NSMutableAttributedString()

        for line in text.components(separatedBy: "\n") {
            if !result.string.isEmpty { result.append(NSAttributedString(string: "\n")) }
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Comment lines (starting with %)
            if trimmed.hasPrefix("%") || trimmed.hasPrefix("#") {
                result.append(NSAttributedString(string: line, attributes: [
                    .font: baseFont, .foregroundColor: NSColor.secondaryLabelColor
                ]))
                continue
            }

            // Key: Value lines
            if let colonIdx = line.firstIndex(of: ":"), colonIdx > line.startIndex {
                let key = String(line[..<colonIdx])
                let rest = String(line[colonIdx...])
                let attrKey = NSMutableAttributedString(string: key, attributes: [
                    .font: boldFont, .foregroundColor: NSColor.systemTeal
                ])
                let attrVal = NSMutableAttributedString(string: rest, attributes: [
                    .font: baseFont, .foregroundColor: NSColor.labelColor
                ])
                // Colorize IPs in value
                let nsRest = rest as NSString
                for match in ipv4Regex.matches(in: rest, range: NSRange(location: 0, length: nsRest.length)) {
                    attrVal.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: match.range)
                }
                attrKey.append(attrVal)
                result.append(attrKey)
                continue
            }

            result.append(NSAttributedString(string: line, attributes: [
                .font: baseFont, .foregroundColor: NSColor.labelColor
            ]))
        }
        return result
    }

    private func showError(_ message: String) {
        isQuerying = false
        queryButton.isEnabled = true
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        statusLabel.stringValue = message
        resultTextView.string = message
    }

    // MARK: - Favorites

    @objc private func toggleFavorite() {
        let target = targetTextField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }
        let existing = QueryFavoritesStorage.favorites(for: "whois")
        if let fav = existing.first(where: { $0.target == target }) {
            QueryFavoritesStorage.remove(id: fav.id)
        } else {
            _ = QueryFavoritesStorage.add(QueryFavorite(type: "whois", target: target))
        }
        refreshFavoritesPopup()
    }

    @objc private func loadFavorite() {
        let index = favoritesPopup.indexOfSelectedItem
        let favorites = QueryFavoritesStorage.favorites(for: "whois")
        guard index > 0, index - 1 < favorites.count else { return }
        targetTextField.stringValue = favorites[index - 1].target
    }

    private func refreshFavoritesPopup() {
        favoritesPopup.removeAllItems()
        favoritesPopup.addItem(withTitle: NSLocalizedString("favorites.button", comment: ""))
        let favorites = QueryFavoritesStorage.favorites(for: "whois")
        if favorites.isEmpty {
            let item = favoritesPopup.menu?.addItem(withTitle: NSLocalizedString("favorites.none", comment: ""), action: nil, keyEquivalent: "")
            item?.isEnabled = false
        } else {
            for fav in favorites { favoritesPopup.addItem(withTitle: fav.target) }
        }
    }
}

/// Wrapper pour capturer Data par référence dans les closures async.
private class DataWrapper {
    var data: Data
    init(data: Data) { self.data = data }
}

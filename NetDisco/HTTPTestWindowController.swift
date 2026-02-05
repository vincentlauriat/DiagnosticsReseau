// HTTPTestWindowController.swift
// NetDisco
//
// Test de disponibilité HTTP/HTTPS. Vérifie le temps de réponse, le code statut,
// la validité SSL et les redirections.

import Cocoa
import Security

// MARK: - Data Model

struct HTTPTestResult: Codable {
    let id: UUID
    let url: String
    let date: Date
    let statusCode: Int?
    let responseTimeMs: Double
    let sslValid: Bool?
    let sslExpiry: Date?
    let sslIssuer: String?
    let redirectChain: [String]
    let errorMessage: String?

    var isSuccess: Bool {
        guard let code = statusCode else { return false }
        return code >= 200 && code < 400
    }
}

// MARK: - Storage

class HTTPTestStorage {
    private static let key = "HTTPTestHistory"
    private static let maxEntries = 50

    static func load() -> [HTTPTestResult] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let results = try? JSONDecoder().decode([HTTPTestResult].self, from: data) else {
            return []
        }
        return results
    }

    static func save(_ results: [HTTPTestResult]) {
        let trimmed = Array(results.prefix(maxEntries))
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func add(_ result: HTTPTestResult) {
        var results = load()
        results.insert(result, at: 0)
        save(results)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - SSL Delegate

class SSLCertificateDelegate: NSObject, URLSessionDelegate {
    var sslValid: Bool?
    var sslExpiry: Date?
    var sslIssuer: String?

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Évaluer la validité
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)
        sslValid = isValid

        // Extraire les infos du certificat
        if let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
           let cert = chain.first {

            // Date d'expiration
            if let certData = SecCertificateCopyData(cert) as Data? {
                // Parser les dates depuis le certificat X.509
                extractCertificateInfo(from: cert)
            }
        }

        completionHandler(.performDefaultHandling, nil)
    }

    private func extractCertificateInfo(from cert: SecCertificate) {
        // Obtenir le nom de l'émetteur
        if let summary = SecCertificateCopySubjectSummary(cert) as String? {
            sslIssuer = summary
        }

        // Pour l'expiration, on utilise les clés OID
        var error: Unmanaged<CFError>?
        if let values = SecCertificateCopyValues(cert, [kSecOIDX509V1ValidityNotAfter] as CFArray, &error) as? [CFString: Any],
           let notAfter = values[kSecOIDX509V1ValidityNotAfter] as? [String: Any],
           let value = notAfter[kSecPropertyKeyValue as String] as? Double {
            // La valeur est en secondes depuis le 1er janvier 2001
            sslExpiry = Date(timeIntervalSinceReferenceDate: value)
        }
    }
}

// MARK: - HTTPTestWindowController

class HTTPTestWindowController: NSWindowController {

    private var urlField: NSTextField!
    private var testButton: NSButton!
    private var progressIndicator: NSProgressIndicator!

    private var statusLabel: NSTextField!
    private var timeLabel: NSTextField!
    private var sslLabel: NSTextField!
    private var redirectLabel: NSTextField!

    private var historyTableView: NSTableView!
    private var history: [HTTPTestResult] = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("httptest.title", comment: "")
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 550, height: 400)
        self.init(window: window)
        setupUI()
        loadHistory()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // URL input
        let urlLabel = NSTextField(labelWithString: "URL :")
        urlLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(urlLabel)

        urlField = NSTextField()
        urlField.placeholderString = "https://example.com"
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.target = self
        urlField.action = #selector(runTest)
        contentView.addSubview(urlField)

        testButton = NSButton(title: NSLocalizedString("httptest.test", comment: ""), target: self, action: #selector(runTest))
        testButton.bezelStyle = .rounded
        testButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(testButton)

        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.isHidden = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(progressIndicator)

        // Results box
        let resultsBox = NSBox()
        resultsBox.title = NSLocalizedString("httptest.results", comment: "")
        resultsBox.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(resultsBox)

        let resultsStack = NSStackView()
        resultsStack.orientation = .vertical
        resultsStack.alignment = .leading
        resultsStack.spacing = 8
        resultsStack.translatesAutoresizingMaskIntoConstraints = false
        resultsBox.contentView = resultsStack

        statusLabel = NSTextField(labelWithString: "—")
        statusLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        resultsStack.addArrangedSubview(statusLabel)

        timeLabel = NSTextField(labelWithString: "—")
        timeLabel.font = NSFont.systemFont(ofSize: 12)
        resultsStack.addArrangedSubview(timeLabel)

        sslLabel = NSTextField(labelWithString: "—")
        sslLabel.font = NSFont.systemFont(ofSize: 12)
        resultsStack.addArrangedSubview(sslLabel)

        redirectLabel = NSTextField(wrappingLabelWithString: "—")
        redirectLabel.font = NSFont.systemFont(ofSize: 11)
        redirectLabel.textColor = .secondaryLabelColor
        resultsStack.addArrangedSubview(redirectLabel)

        // History
        let historyLabel = NSTextField(labelWithString: NSLocalizedString("httptest.history", comment: ""))
        historyLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        historyLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(historyLabel)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)

        historyTableView = NSTableView()
        historyTableView.dataSource = self
        historyTableView.delegate = self
        historyTableView.rowHeight = 24
        historyTableView.usesAlternatingRowBackgroundColors = true

        let urlCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("url"))
        urlCol.title = "URL"
        urlCol.width = 200
        historyTableView.addTableColumn(urlCol)

        let dateCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateCol.title = NSLocalizedString("httptest.column.date", comment: "")
        dateCol.width = 100
        historyTableView.addTableColumn(dateCol)

        let statusCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        statusCol.title = NSLocalizedString("httptest.column.status", comment: "")
        statusCol.width = 60
        historyTableView.addTableColumn(statusCol)

        let timeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("time"))
        timeCol.title = NSLocalizedString("httptest.column.time", comment: "")
        timeCol.width = 70
        historyTableView.addTableColumn(timeCol)

        let sslCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ssl"))
        sslCol.title = "SSL"
        sslCol.width = 50
        historyTableView.addTableColumn(sslCol)

        scrollView.documentView = historyTableView

        // Buttons
        let clearButton = NSButton(title: NSLocalizedString("httptest.clear", comment: ""), target: self, action: #selector(clearHistory))
        clearButton.bezelStyle = .rounded
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(clearButton)

        let copyButton = NSButton(title: NSLocalizedString("httptest.copy", comment: ""), target: self, action: #selector(copyResult))
        copyButton.bezelStyle = .rounded
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(copyButton)

        NSLayoutConstraint.activate([
            urlLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            urlLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            urlField.centerYAnchor.constraint(equalTo: urlLabel.centerYAnchor),
            urlField.leadingAnchor.constraint(equalTo: urlLabel.trailingAnchor, constant: 8),
            urlField.trailingAnchor.constraint(equalTo: testButton.leadingAnchor, constant: -8),

            testButton.centerYAnchor.constraint(equalTo: urlLabel.centerYAnchor),
            testButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            testButton.widthAnchor.constraint(equalToConstant: 80),

            progressIndicator.centerYAnchor.constraint(equalTo: testButton.centerYAnchor),
            progressIndicator.trailingAnchor.constraint(equalTo: testButton.leadingAnchor, constant: -8),

            resultsBox.topAnchor.constraint(equalTo: urlLabel.bottomAnchor, constant: 16),
            resultsBox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            resultsBox.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            resultsBox.heightAnchor.constraint(equalToConstant: 120),

            historyLabel.topAnchor.constraint(equalTo: resultsBox.bottomAnchor, constant: 16),
            historyLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            scrollView.topAnchor.constraint(equalTo: historyLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: clearButton.topAnchor, constant: -12),

            clearButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            clearButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            copyButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            copyButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
        ])
    }

    private func loadHistory() {
        history = HTTPTestStorage.load()
        historyTableView.reloadData()
    }

    // MARK: - Actions

    @objc private func runTest() {
        var urlString = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !urlString.isEmpty else { return }

        // Ajouter https:// si manquant
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }

        guard let url = URL(string: urlString) else {
            showError(NSLocalizedString("httptest.error.invalid_url", comment: ""))
            return
        }

        testButton.isEnabled = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)

        performTest(url: url) { [weak self] result in
            DispatchQueue.main.async {
                self?.testButton.isEnabled = true
                self?.progressIndicator.stopAnimation(nil)
                self?.progressIndicator.isHidden = true
                self?.displayResult(result)

                HTTPTestStorage.add(result)
                self?.loadHistory()
            }
        }
    }

    private func performTest(url: URL, completion: @escaping (HTTPTestResult) -> Void) {
        let sslDelegate = SSLCertificateDelegate()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30

        let session = URLSession(configuration: config, delegate: sslDelegate, delegateQueue: nil)

        var redirectChain: [String] = [url.absoluteString]
        let startTime = CFAbsoluteTimeGetCurrent()

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let task = session.dataTask(with: request) { data, response, error in
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

            var result: HTTPTestResult

            if let error = error {
                result = HTTPTestResult(
                    id: UUID(),
                    url: url.absoluteString,
                    date: Date(),
                    statusCode: nil,
                    responseTimeMs: elapsed,
                    sslValid: sslDelegate.sslValid,
                    sslExpiry: sslDelegate.sslExpiry,
                    sslIssuer: sslDelegate.sslIssuer,
                    redirectChain: redirectChain,
                    errorMessage: error.localizedDescription
                )
            } else if let httpResponse = response as? HTTPURLResponse {
                // Collecter la chaîne de redirections depuis la réponse finale
                if let finalURL = httpResponse.url?.absoluteString, finalURL != url.absoluteString {
                    redirectChain.append(finalURL)
                }

                result = HTTPTestResult(
                    id: UUID(),
                    url: url.absoluteString,
                    date: Date(),
                    statusCode: httpResponse.statusCode,
                    responseTimeMs: elapsed,
                    sslValid: url.scheme == "https" ? sslDelegate.sslValid : nil,
                    sslExpiry: sslDelegate.sslExpiry,
                    sslIssuer: sslDelegate.sslIssuer,
                    redirectChain: redirectChain,
                    errorMessage: nil
                )
            } else {
                result = HTTPTestResult(
                    id: UUID(),
                    url: url.absoluteString,
                    date: Date(),
                    statusCode: nil,
                    responseTimeMs: elapsed,
                    sslValid: nil,
                    sslExpiry: nil,
                    sslIssuer: nil,
                    redirectChain: redirectChain,
                    errorMessage: NSLocalizedString("httptest.error.unknown", comment: "")
                )
            }

            completion(result)
        }

        task.resume()
    }

    private func displayResult(_ result: HTTPTestResult) {
        // Status
        if let code = result.statusCode {
            let statusText = HTTPURLResponse.localizedString(forStatusCode: code).capitalized
            if result.isSuccess {
                statusLabel.stringValue = "✓ \(code) \(statusText)"
                statusLabel.textColor = .systemGreen
            } else {
                statusLabel.stringValue = "✗ \(code) \(statusText)"
                statusLabel.textColor = .systemRed
            }
        } else if let error = result.errorMessage {
            statusLabel.stringValue = "✗ " + error
            statusLabel.textColor = .systemRed
        } else {
            statusLabel.stringValue = "—"
            statusLabel.textColor = .labelColor
        }

        // Time
        timeLabel.stringValue = String(format: NSLocalizedString("httptest.response_time", comment: ""), result.responseTimeMs)

        // SSL
        if let valid = result.sslValid {
            if valid {
                var sslText = "✓ SSL " + NSLocalizedString("httptest.ssl.valid", comment: "")
                if let expiry = result.sslExpiry {
                    let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
                    sslText += String(format: NSLocalizedString("httptest.ssl.expires_in", comment: ""), days)
                }
                sslLabel.stringValue = sslText
                sslLabel.textColor = .systemGreen
            } else {
                sslLabel.stringValue = "✗ SSL " + NSLocalizedString("httptest.ssl.invalid", comment: "")
                sslLabel.textColor = .systemRed
            }
        } else {
            sslLabel.stringValue = NSLocalizedString("httptest.ssl.none", comment: "")
            sslLabel.textColor = .secondaryLabelColor
        }

        // Redirections
        if result.redirectChain.count > 1 {
            redirectLabel.stringValue = NSLocalizedString("httptest.redirects", comment: "") + ": " + result.redirectChain.joined(separator: " → ")
        } else {
            redirectLabel.stringValue = NSLocalizedString("httptest.no_redirects", comment: "")
        }
    }

    private func showError(_ message: String) {
        statusLabel.stringValue = "✗ " + message
        statusLabel.textColor = .systemRed
        timeLabel.stringValue = "—"
        sslLabel.stringValue = "—"
        redirectLabel.stringValue = "—"
    }

    @objc private func clearHistory() {
        HTTPTestStorage.clear()
        loadHistory()
    }

    @objc private func copyResult() {
        var text = statusLabel.stringValue + "\n"
        text += timeLabel.stringValue + "\n"
        text += sslLabel.stringValue + "\n"
        text += redirectLabel.stringValue
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension HTTPTestWindowController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return history.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < history.count else { return nil }
        let result = history[row]

        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("")
        let cellIdentifier = NSUserInterfaceItemIdentifier("HTTPCell_\(identifier.rawValue)")

        let textField: NSTextField
        if let existing = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTextField {
            textField = existing
        } else {
            textField = NSTextField(labelWithString: "")
            textField.identifier = cellIdentifier
            textField.font = NSFont.systemFont(ofSize: 11)
        }

        switch identifier.rawValue {
        case "url":
            textField.stringValue = result.url
            textField.textColor = .labelColor
        case "date":
            let df = DateFormatter()
            df.dateStyle = .short
            df.timeStyle = .short
            textField.stringValue = df.string(from: result.date)
            textField.textColor = .secondaryLabelColor
        case "status":
            if let code = result.statusCode {
                textField.stringValue = "\(code)"
                textField.textColor = result.isSuccess ? .systemGreen : .systemRed
            } else {
                textField.stringValue = "—"
                textField.textColor = .systemRed
            }
        case "time":
            textField.stringValue = String(format: "%.0f ms", result.responseTimeMs)
            textField.textColor = .labelColor
        case "ssl":
            if let valid = result.sslValid {
                textField.stringValue = valid ? "✓" : "✗"
                textField.textColor = valid ? .systemGreen : .systemRed
            } else {
                textField.stringValue = "—"
                textField.textColor = .tertiaryLabelColor
            }
        default:
            textField.stringValue = ""
        }

        return textField
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = historyTableView.selectedRow
        guard row >= 0 && row < history.count else { return }

        let result = history[row]
        urlField.stringValue = result.url
        displayResult(result)
    }
}

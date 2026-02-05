// SSLInspectorWindowController.swift
// NetDisco
//
// Inspecteur de certificats SSL. Affiche les détails du certificat d'un domaine :
// sujet, émetteur, dates de validité, chaîne de certification.
// Utilise Network.framework avec NWConnection pour capturer les certificats SSL.

import Cocoa
import Network
import Security

// MARK: - Certificate Info

struct CertificateInfo {
    let subject: String
    let issuer: String
    let validFrom: Date?
    let validTo: Date?
    let serialNumber: String
    let signatureAlgorithm: String
    let publicKeyInfo: String
    let isValid: Bool
    let chain: [CertificateChainItem]

    var daysUntilExpiry: Int? {
        guard let validTo = validTo else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: validTo).day
    }

    var isExpiringSoon: Bool {
        guard let days = daysUntilExpiry else { return false }
        return days < 30
    }
}

struct CertificateChainItem {
    let subject: String
    let issuer: String
    let depth: Int
}

// MARK: - SSLInspectorWindowController

class SSLInspectorWindowController: NSWindowController {

    private var domainField: NSTextField!
    private var inspectButton: NSButton!
    private var progressIndicator: NSProgressIndicator!

    private var warningLabel: NSTextField!
    private var detailsTextView: NSTextView!
    private var chainOutlineView: NSOutlineView!

    private var currentCertInfo: CertificateInfo?
    private var currentConnection: NWConnection?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("ssl.title", comment: "")
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 400)
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Domain input
        let domainLabel = NSTextField(labelWithString: NSLocalizedString("ssl.domain", comment: "") + " :")
        domainLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        domainLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(domainLabel)

        domainField = NSTextField()
        domainField.placeholderString = "example.com"
        domainField.translatesAutoresizingMaskIntoConstraints = false
        domainField.target = self
        domainField.action = #selector(inspect)
        contentView.addSubview(domainField)

        inspectButton = NSButton(title: NSLocalizedString("ssl.inspect", comment: ""), target: self, action: #selector(inspect))
        inspectButton.bezelStyle = .rounded
        inspectButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(inspectButton)

        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.isHidden = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(progressIndicator)

        // Warning label
        warningLabel = NSTextField(labelWithString: "")
        warningLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        warningLabel.textColor = .systemOrange
        warningLabel.translatesAutoresizingMaskIntoConstraints = false
        warningLabel.isHidden = true
        contentView.addSubview(warningLabel)

        // Details label
        let detailsLabel = NSTextField(labelWithString: NSLocalizedString("ssl.details", comment: ""))
        detailsLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        detailsLabel.textColor = .secondaryLabelColor
        detailsLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(detailsLabel)

        let detailsScroll = NSScrollView()
        detailsScroll.hasVerticalScroller = true
        detailsScroll.borderType = .bezelBorder
        detailsScroll.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(detailsScroll)

        detailsTextView = NSTextView()
        detailsTextView.isEditable = false
        detailsTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        detailsTextView.backgroundColor = NSColor.textBackgroundColor
        detailsTextView.textContainerInset = NSSize(width: 8, height: 8)
        detailsTextView.autoresizingMask = [.width, .height]
        detailsScroll.documentView = detailsTextView

        // Chain label
        let chainLabel = NSTextField(labelWithString: NSLocalizedString("ssl.chain", comment: ""))
        chainLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        chainLabel.textColor = .secondaryLabelColor
        chainLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(chainLabel)

        let chainScroll = NSScrollView()
        chainScroll.hasVerticalScroller = true
        chainScroll.borderType = .bezelBorder
        chainScroll.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(chainScroll)

        chainOutlineView = NSOutlineView()
        chainOutlineView.dataSource = self
        chainOutlineView.delegate = self
        chainOutlineView.headerView = nil
        chainOutlineView.rowHeight = 24

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("chain"))
        col.width = 500
        chainOutlineView.addTableColumn(col)
        chainOutlineView.outlineTableColumn = col

        chainScroll.documentView = chainOutlineView

        // Copy button
        let copyButton = NSButton(title: NSLocalizedString("ssl.copy", comment: ""), target: self, action: #selector(copyDetails))
        copyButton.bezelStyle = .rounded
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(copyButton)

        // Layout
        NSLayoutConstraint.activate([
            domainLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            domainLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            domainField.centerYAnchor.constraint(equalTo: domainLabel.centerYAnchor),
            domainField.leadingAnchor.constraint(equalTo: domainLabel.trailingAnchor, constant: 8),
            domainField.trailingAnchor.constraint(equalTo: inspectButton.leadingAnchor, constant: -8),

            inspectButton.centerYAnchor.constraint(equalTo: domainLabel.centerYAnchor),
            inspectButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            inspectButton.widthAnchor.constraint(equalToConstant: 100),

            progressIndicator.centerYAnchor.constraint(equalTo: inspectButton.centerYAnchor),
            progressIndicator.trailingAnchor.constraint(equalTo: inspectButton.leadingAnchor, constant: -8),

            warningLabel.topAnchor.constraint(equalTo: domainLabel.bottomAnchor, constant: 12),
            warningLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            warningLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            detailsLabel.topAnchor.constraint(equalTo: warningLabel.bottomAnchor, constant: 12),
            detailsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            detailsScroll.topAnchor.constraint(equalTo: detailsLabel.bottomAnchor, constant: 4),
            detailsScroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            detailsScroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            detailsScroll.heightAnchor.constraint(equalToConstant: 160),

            chainLabel.topAnchor.constraint(equalTo: detailsScroll.bottomAnchor, constant: 16),
            chainLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            chainScroll.topAnchor.constraint(equalTo: chainLabel.bottomAnchor, constant: 4),
            chainScroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            chainScroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            chainScroll.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -16),

            copyButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            copyButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
        ])
    }

    // MARK: - Actions

    @objc private func inspect() {
        var domain = domainField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !domain.isEmpty else { return }

        // Nettoyer le domaine
        if domain.hasPrefix("https://") {
            domain = String(domain.dropFirst(8))
        } else if domain.hasPrefix("http://") {
            domain = String(domain.dropFirst(7))
        }
        if let slashIndex = domain.firstIndex(of: "/") {
            domain = String(domain[..<slashIndex])
        }

        inspectButton.isEnabled = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        warningLabel.isHidden = true

        // Annuler la connexion précédente si elle existe
        currentConnection?.cancel()

        // Créer les options TLS avec un bloc de vérification personnalisé
        let tlsOptions = NWProtocolTLS.Options()

        // Définir le bloc de vérification pour capturer les certificats
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { [weak self] metadata, trust, complete in
                // Extraire les informations du certificat sur le thread principal
                DispatchQueue.main.async {
                    self?.processCertificates(trust: trust, domain: domain)
                }
                // Accepter le certificat (on fait juste l'inspection)
                complete(true)
            },
            .main
        )

        // Créer la connexion
        let tcpOptions = NWProtocolTCP.Options()
        let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)

        let host = NWEndpoint.Host(domain)
        let port = NWEndpoint.Port(integerLiteral: 443)
        let connection = NWConnection(host: host, port: port, using: params)

        currentConnection = connection

        // Timeout
        var timeoutWorkItem: DispatchWorkItem?
        timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.currentCertInfo == nil {
                self.finishInspection()
                self.showError(NSLocalizedString("ssl.error.timeout", comment: ""))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeoutWorkItem!)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                timeoutWorkItem?.cancel()
                // La connexion TLS est établie, les certificats ont été capturés
                DispatchQueue.main.async {
                    self?.finishInspection()
                }
            case .failed(let error):
                timeoutWorkItem?.cancel()
                DispatchQueue.main.async {
                    self?.finishInspection()
                    self?.showError(error.localizedDescription)
                }
            case .cancelled:
                timeoutWorkItem?.cancel()
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
    }

    private func processCertificates(trust: sec_trust_t, domain: String) {
        // Convertir sec_trust_t en SecTrust
        let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()

        // Évaluer la validité
        var cfError: CFError?
        let isValid = SecTrustEvaluateWithError(secTrust, &cfError)

        // Extraire la chaîne de certificats
        guard let certificates = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate],
              let leafCert = certificates.first else {
            showError(NSLocalizedString("ssl.error.no_cert", comment: ""))
            return
        }

        // Extraire les infos du certificat principal
        let subject = extractSubject(from: leafCert)
        let issuer = extractIssuer(from: leafCert)
        let (validFrom, validTo) = extractDates(from: leafCert)
        let serialNumber = extractSerialNumber(from: leafCert)
        let signatureAlgorithm = extractSignatureAlgorithm(from: leafCert)
        let publicKeyInfo = extractPublicKeyInfo(from: leafCert)

        // Construire la chaîne
        var chain: [CertificateChainItem] = []
        for (index, cert) in certificates.enumerated() {
            chain.append(CertificateChainItem(
                subject: extractSubject(from: cert),
                issuer: extractIssuer(from: cert),
                depth: index
            ))
        }

        currentCertInfo = CertificateInfo(
            subject: subject,
            issuer: issuer,
            validFrom: validFrom,
            validTo: validTo,
            serialNumber: serialNumber,
            signatureAlgorithm: signatureAlgorithm,
            publicKeyInfo: publicKeyInfo,
            isValid: isValid,
            chain: chain
        )
    }

    private func finishInspection() {
        inspectButton.isEnabled = true
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true

        currentConnection?.cancel()
        currentConnection = nil

        if let certInfo = currentCertInfo {
            displayCertificate(certInfo)
        }
    }

    private func displayCertificate(_ info: CertificateInfo) {
        currentCertInfo = info

        // Warning
        if !info.isValid {
            warningLabel.stringValue = "⚠️ " + NSLocalizedString("ssl.warning.invalid", comment: "")
            warningLabel.textColor = .systemRed
            warningLabel.isHidden = false
        } else if info.isExpiringSoon {
            warningLabel.stringValue = String(format: NSLocalizedString("ssl.warning.expiring", comment: ""), info.daysUntilExpiry ?? 0)
            warningLabel.textColor = .systemOrange
            warningLabel.isHidden = false
        } else {
            // Certificat valide
            warningLabel.stringValue = "✓ " + NSLocalizedString("ssl.valid", comment: "")
            warningLabel.textColor = .systemGreen
            warningLabel.isHidden = false
        }

        // Details
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short

        var details = ""
        details += NSLocalizedString("ssl.subject", comment: "") + ": \(info.subject)\n"
        details += String(format: NSLocalizedString("ssl.issued_by", comment: ""), info.issuer) + "\n"
        details += "\n"

        if let validFrom = info.validFrom {
            details += String(format: NSLocalizedString("ssl.valid_from", comment: ""), df.string(from: validFrom)) + "\n"
        }
        if let validTo = info.validTo {
            details += String(format: NSLocalizedString("ssl.valid_to", comment: ""), df.string(from: validTo))
            if let days = info.daysUntilExpiry {
                details += " (" + String(format: NSLocalizedString("ssl.days", comment: ""), days) + ")"
            }
            details += "\n"
        }

        details += "\n"
        details += String(format: NSLocalizedString("ssl.serial", comment: ""), info.serialNumber) + "\n"
        details += String(format: NSLocalizedString("ssl.algorithm", comment: ""), info.signatureAlgorithm) + "\n"
        details += String(format: NSLocalizedString("ssl.public_key", comment: ""), info.publicKeyInfo) + "\n"

        detailsTextView.string = details

        // Chain
        chainOutlineView.reloadData()
        chainOutlineView.expandItem(nil, expandChildren: true)
    }

    private func showError(_ message: String) {
        currentCertInfo = nil
        warningLabel.stringValue = "✗ " + message
        warningLabel.textColor = .systemRed
        warningLabel.isHidden = false
        detailsTextView.string = ""
        chainOutlineView.reloadData()
    }

    // MARK: - Certificate Extraction

    private func extractSubject(from cert: SecCertificate) -> String {
        if let summary = SecCertificateCopySubjectSummary(cert) as String? {
            return summary
        }
        return NSLocalizedString("ssl.unknown", comment: "")
    }

    private func extractIssuer(from cert: SecCertificate) -> String {
        var error: Unmanaged<CFError>?
        guard let values = SecCertificateCopyValues(cert, [kSecOIDX509V1IssuerName] as CFArray, &error) as? [CFString: Any],
              let issuerDict = values[kSecOIDX509V1IssuerName] as? [String: Any],
              let issuerValue = issuerDict[kSecPropertyKeyValue as String] as? [[String: Any]] else {
            return NSLocalizedString("ssl.unknown", comment: "")
        }

        // Chercher le CN (Common Name)
        for item in issuerValue {
            if let label = item[kSecPropertyKeyLabel as String] as? String,
               label == "2.5.4.3",  // OID for CN
               let value = item[kSecPropertyKeyValue as String] as? String {
                return value
            }
        }

        // Fallback: prendre le premier O (Organization)
        for item in issuerValue {
            if let label = item[kSecPropertyKeyLabel as String] as? String,
               label == "2.5.4.10",  // OID for O
               let value = item[kSecPropertyKeyValue as String] as? String {
                return value
            }
        }

        return NSLocalizedString("ssl.unknown", comment: "")
    }

    private func extractDates(from cert: SecCertificate) -> (Date?, Date?) {
        var error: Unmanaged<CFError>?
        guard let values = SecCertificateCopyValues(cert, [kSecOIDX509V1ValidityNotBefore, kSecOIDX509V1ValidityNotAfter] as CFArray, &error) as? [CFString: Any] else {
            return (nil, nil)
        }

        var validFrom: Date?
        var validTo: Date?

        if let notBeforeDict = values[kSecOIDX509V1ValidityNotBefore] as? [String: Any],
           let notBeforeValue = notBeforeDict[kSecPropertyKeyValue as String] as? Double {
            validFrom = Date(timeIntervalSinceReferenceDate: notBeforeValue)
        }

        if let notAfterDict = values[kSecOIDX509V1ValidityNotAfter] as? [String: Any],
           let notAfterValue = notAfterDict[kSecPropertyKeyValue as String] as? Double {
            validTo = Date(timeIntervalSinceReferenceDate: notAfterValue)
        }

        return (validFrom, validTo)
    }

    private func extractSerialNumber(from cert: SecCertificate) -> String {
        var error: Unmanaged<CFError>?
        guard let values = SecCertificateCopyValues(cert, [kSecOIDX509V1SerialNumber] as CFArray, &error) as? [CFString: Any],
              let serialDict = values[kSecOIDX509V1SerialNumber] as? [String: Any],
              let serialValue = serialDict[kSecPropertyKeyValue as String] as? Data else {
            return NSLocalizedString("ssl.unknown", comment: "")
        }

        return serialValue.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    private func extractSignatureAlgorithm(from cert: SecCertificate) -> String {
        var error: Unmanaged<CFError>?
        guard let values = SecCertificateCopyValues(cert, [kSecOIDX509V1SignatureAlgorithm] as CFArray, &error) as? [CFString: Any],
              let sigDict = values[kSecOIDX509V1SignatureAlgorithm] as? [String: Any],
              let sigValue = sigDict[kSecPropertyKeyValue as String] as? String else {
            return NSLocalizedString("ssl.unknown", comment: "")
        }
        return sigValue
    }

    private func extractPublicKeyInfo(from cert: SecCertificate) -> String {
        guard let publicKey = SecCertificateCopyKey(cert) else {
            return NSLocalizedString("ssl.unknown", comment: "")
        }

        guard let attributes = SecKeyCopyAttributes(publicKey) as? [CFString: Any] else {
            return NSLocalizedString("ssl.unknown", comment: "")
        }

        let keyType = attributes[kSecAttrKeyType] as? String ?? ""
        let keySize = attributes[kSecAttrKeySizeInBits] as? Int ?? 0

        let typeString: String
        switch keyType {
        case String(kSecAttrKeyTypeRSA):
            typeString = "RSA"
        case String(kSecAttrKeyTypeECSECPrimeRandom):
            typeString = "ECDSA"
        default:
            typeString = keyType
        }

        return "\(typeString) \(keySize) bits"
    }

    @objc private func copyDetails() {
        guard let info = currentCertInfo else { return }

        var text = NSLocalizedString("ssl.title", comment: "") + ": " + domainField.stringValue + "\n"
        text += String(repeating: "─", count: 40) + "\n\n"
        text += detailsTextView.string + "\n"
        text += NSLocalizedString("ssl.chain", comment: "") + ":\n"
        for item in info.chain {
            let indent = String(repeating: "  ", count: item.depth)
            text += "\(indent)├─ \(item.subject)\n"
            text += "\(indent)   " + NSLocalizedString("ssl.issued_by", comment: "") + ": \(item.issuer)\n"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Cleanup

    override func close() {
        currentConnection?.cancel()
        currentConnection = nil
        super.close()
    }
}

// MARK: - NSOutlineViewDataSource & Delegate

extension SSLInspectorWindowController: NSOutlineViewDataSource, NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let info = currentCertInfo else { return 0 }
        if item == nil {
            return info.chain.isEmpty ? 0 : 1  // Root
        }
        if let chainItem = item as? CertificateChainItem {
            let nextDepth = chainItem.depth + 1
            return info.chain.filter { $0.depth == nextDepth }.count > 0 ? 1 : 0
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let info = currentCertInfo else { return "" }
        if item == nil {
            return info.chain.first ?? ""
        }
        if let chainItem = item as? CertificateChainItem {
            let nextDepth = chainItem.depth + 1
            if let next = info.chain.first(where: { $0.depth == nextDepth }) {
                return next
            }
        }
        return ""
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let info = currentCertInfo, let chainItem = item as? CertificateChainItem else { return false }
        let nextDepth = chainItem.depth + 1
        return info.chain.contains { $0.depth == nextDepth }
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let chainItem = item as? CertificateChainItem else { return nil }

        let cellIdentifier = NSUserInterfaceItemIdentifier("ChainCell")
        let textField: NSTextField

        if let existing = outlineView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTextField {
            textField = existing
        } else {
            textField = NSTextField(labelWithString: "")
            textField.identifier = cellIdentifier
            textField.font = NSFont.systemFont(ofSize: 12)
        }

        textField.stringValue = "\(chainItem.subject) (\(chainItem.issuer))"
        return textField
    }
}

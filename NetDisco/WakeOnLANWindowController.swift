// WakeOnLANWindowController.swift
// NetDisco
//
// Wake on LAN - Envoie un magic packet pour réveiller des appareils sur le réseau local.
// Gère une liste d'appareils enregistrés avec leur adresse MAC.

import Cocoa
import Darwin

// MARK: - Data Model

struct WoLDevice: Codable, Identifiable {
    let id: UUID
    var name: String
    var macAddress: String
    var lastUsed: Date?
    var lastSuccess: Bool?

    init(name: String, macAddress: String) {
        self.id = UUID()
        self.name = name
        self.macAddress = macAddress.uppercased()
        self.lastUsed = nil
        self.lastSuccess = nil
    }
}

// MARK: - Storage

class WoLDeviceStorage {
    private static let key = "WoLDevices"
    private static let maxDevices = 20

    static func load() -> [WoLDevice] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let devices = try? JSONDecoder().decode([WoLDevice].self, from: data) else {
            return []
        }
        return devices
    }

    static func save(_ devices: [WoLDevice]) {
        let trimmed = Array(devices.prefix(maxDevices))
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func add(_ device: WoLDevice) {
        var devices = load()
        devices.insert(device, at: 0)
        save(devices)
    }

    static func remove(id: UUID) {
        var devices = load()
        devices.removeAll { $0.id == id }
        save(devices)
    }

    static func update(_ device: WoLDevice) {
        var devices = load()
        if let idx = devices.firstIndex(where: { $0.id == device.id }) {
            devices[idx] = device
            save(devices)
        }
    }
}

// MARK: - WakeOnLANWindowController

class WakeOnLANWindowController: NSWindowController {

    private var tableView: NSTableView!
    private var devices: [WoLDevice] = []

    private var nameField: NSTextField!
    private var macField: NSTextField!
    private var statusLabel: NSTextField!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("wol.title", comment: "")
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 450, height: 350)
        self.init(window: window)
        setupUI()
        loadDevices()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Title
        let titleLabel = NSTextField(labelWithString: NSLocalizedString("wol.devices", comment: ""))
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        // Table
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)

        tableView = NSTableView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 28
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false

        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = NSLocalizedString("wol.column.name", comment: "")
        nameCol.width = 150
        tableView.addTableColumn(nameCol)

        let macCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("mac"))
        macCol.title = NSLocalizedString("wol.column.mac", comment: "")
        macCol.width = 140
        tableView.addTableColumn(macCol)

        let lastCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("last"))
        lastCol.title = NSLocalizedString("wol.column.last", comment: "")
        lastCol.width = 120
        tableView.addTableColumn(lastCol)

        let actionCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionCol.title = ""
        actionCol.width = 80
        tableView.addTableColumn(actionCol)

        scrollView.documentView = tableView

        // Add device form
        let formBox = NSBox()
        formBox.title = NSLocalizedString("wol.add_device", comment: "")
        formBox.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(formBox)

        let formStack = NSStackView()
        formStack.orientation = .vertical
        formStack.spacing = 8
        formStack.alignment = .leading
        formStack.translatesAutoresizingMaskIntoConstraints = false

        // Ajouter le formStack au contentView du box avec contraintes
        if let boxContentView = formBox.contentView {
            boxContentView.addSubview(formStack)
            NSLayoutConstraint.activate([
                formStack.topAnchor.constraint(equalTo: boxContentView.topAnchor, constant: 8),
                formStack.leadingAnchor.constraint(equalTo: boxContentView.leadingAnchor, constant: 8),
                formStack.trailingAnchor.constraint(lessThanOrEqualTo: boxContentView.trailingAnchor, constant: -8),
                formStack.bottomAnchor.constraint(equalTo: boxContentView.bottomAnchor, constant: -8)
            ])
        }

        // Name row
        let nameRow = NSStackView()
        nameRow.orientation = .horizontal
        nameRow.spacing = 8
        let nameLabel = NSTextField(labelWithString: NSLocalizedString("wol.name", comment: "") + " :")
        nameLabel.widthAnchor.constraint(equalToConstant: 80).isActive = true
        nameField = NSTextField()
        nameField.placeholderString = NSLocalizedString("wol.name.placeholder", comment: "")
        nameField.widthAnchor.constraint(equalToConstant: 200).isActive = true
        nameRow.addArrangedSubview(nameLabel)
        nameRow.addArrangedSubview(nameField)
        formStack.addArrangedSubview(nameRow)

        // MAC row
        let macRow = NSStackView()
        macRow.orientation = .horizontal
        macRow.spacing = 8
        let macLabel = NSTextField(labelWithString: NSLocalizedString("wol.mac", comment: "") + " :")
        macLabel.widthAnchor.constraint(equalToConstant: 80).isActive = true
        macField = NSTextField()
        macField.placeholderString = "AA:BB:CC:DD:EE:FF"
        macField.widthAnchor.constraint(equalToConstant: 200).isActive = true
        macRow.addArrangedSubview(macLabel)
        macRow.addArrangedSubview(macField)
        formStack.addArrangedSubview(macRow)

        // Add button
        let addButton = NSButton(title: NSLocalizedString("wol.add", comment: ""), target: self, action: #selector(addDevice))
        addButton.bezelStyle = .rounded
        formStack.addArrangedSubview(addButton)

        // Status
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusLabel)

        // Bottom buttons
        let deleteButton = NSButton(title: NSLocalizedString("wol.delete", comment: ""), target: self, action: #selector(deleteSelected))
        deleteButton.bezelStyle = .rounded
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(deleteButton)

        let wakeAllButton = NSButton(title: NSLocalizedString("wol.wake_selected", comment: ""), target: self, action: #selector(wakeSelected))
        wakeAllButton.bezelStyle = .rounded
        wakeAllButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(wakeAllButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.heightAnchor.constraint(equalToConstant: 150),

            formBox.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 16),
            formBox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            formBox.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            statusLabel.topAnchor.constraint(equalTo: formBox.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            deleteButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            deleteButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            wakeAllButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            wakeAllButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }

    private func loadDevices() {
        devices = WoLDeviceStorage.load()
        tableView.reloadData()
    }

    // MARK: - Actions

    @objc private func addDevice() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        var mac = macField.stringValue.trimmingCharacters(in: .whitespaces).uppercased()

        // Normaliser le format MAC (supporter différents séparateurs)
        mac = mac.replacingOccurrences(of: "-", with: ":")
        mac = mac.replacingOccurrences(of: " ", with: ":")

        // Ajouter les ":" si manquants (format AABBCCDDEEFF)
        if mac.count == 12 && !mac.contains(":") {
            var formatted = ""
            for (i, char) in mac.enumerated() {
                if i > 0 && i % 2 == 0 { formatted += ":" }
                formatted.append(char)
            }
            mac = formatted
        }

        guard !name.isEmpty else {
            showStatus(NSLocalizedString("wol.error.name_required", comment: ""), isError: true)
            return
        }

        guard isValidMAC(mac) else {
            showStatus(NSLocalizedString("wol.error.invalid_mac", comment: ""), isError: true)
            return
        }

        // Vérifier si déjà existant
        if devices.contains(where: { $0.macAddress == mac }) {
            showStatus(NSLocalizedString("wol.error.duplicate", comment: ""), isError: true)
            return
        }

        let device = WoLDevice(name: name, macAddress: mac)
        WoLDeviceStorage.add(device)
        loadDevices()

        nameField.stringValue = ""
        macField.stringValue = ""
        showStatus(NSLocalizedString("wol.device_added", comment: ""), isError: false)
    }

    @objc private func deleteSelected() {
        let row = tableView.selectedRow
        guard row >= 0 && row < devices.count else { return }

        let device = devices[row]
        WoLDeviceStorage.remove(id: device.id)
        loadDevices()
        showStatus(NSLocalizedString("wol.device_deleted", comment: ""), isError: false)
    }

    @objc private func wakeSelected() {
        let row = tableView.selectedRow
        guard row >= 0 && row < devices.count else {
            showStatus(NSLocalizedString("wol.error.select_device", comment: ""), isError: true)
            return
        }

        wakeDevice(at: row)
    }

    @objc private func wakeDeviceAtRow(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0 && row < devices.count else { return }
        wakeDevice(at: row)
    }

    private func wakeDevice(at row: Int) {
        var device = devices[row]
        let success = sendMagicPacket(macAddress: device.macAddress)

        device.lastUsed = Date()
        device.lastSuccess = success
        WoLDeviceStorage.update(device)
        loadDevices()

        if success {
            showStatus(String(format: NSLocalizedString("wol.packet_sent", comment: ""), device.name), isError: false)
        } else {
            showStatus(NSLocalizedString("wol.error.send_failed", comment: ""), isError: true)
        }
    }

    // MARK: - Magic Packet

    private func sendMagicPacket(macAddress: String) -> Bool {
        // Parser l'adresse MAC
        let macBytes = macAddress.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        guard macBytes.count == 6 else { return false }

        // Construire le magic packet (102 octets)
        // 6 octets de 0xFF + 16 répétitions de l'adresse MAC
        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }

        // Créer le socket UDP
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return false }
        defer { Darwin.close(sock) }

        // Activer le broadcast
        var broadcastEnable: Int32 = 1
        let optResult = setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, socklen_t(MemoryLayout<Int32>.size))
        guard optResult == 0 else { return false }

        // Adresse broadcast (255.255.255.255:9)
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(9).bigEndian  // Port standard WoL
        addr.sin_addr.s_addr = INADDR_BROADCAST

        // Envoyer le paquet
        let sent = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                packet.withUnsafeBytes { buf in
                    sendto(sock, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        return sent == packet.count
    }

    // MARK: - Validation

    private func isValidMAC(_ mac: String) -> Bool {
        let parts = mac.split(separator: ":")
        guard parts.count == 6 else { return false }
        return parts.allSatisfy { part in
            part.count == 2 && part.allSatisfy { $0.isHexDigit }
        }
    }

    // MARK: - UI Helpers

    private func showStatus(_ message: String, isError: Bool) {
        statusLabel.stringValue = message
        statusLabel.textColor = isError ? .systemRed : .systemGreen

        // Effacer après 5 secondes
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.statusLabel.stringValue = ""
        }
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension WakeOnLANWindowController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return devices.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < devices.count else { return nil }
        let device = devices[row]

        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("")

        if identifier.rawValue == "action" {
            // Bouton Wake
            let button = NSButton(title: NSLocalizedString("wol.wake", comment: ""), target: self, action: #selector(wakeDeviceAtRow))
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.tag = row
            return button
        }

        let cellIdentifier = NSUserInterfaceItemIdentifier("WoLCell_\(identifier.rawValue)")
        let textField: NSTextField

        if let existing = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTextField {
            textField = existing
        } else {
            textField = NSTextField(labelWithString: "")
            textField.identifier = cellIdentifier
            textField.font = NSFont.systemFont(ofSize: 12)
        }

        switch identifier.rawValue {
        case "name":
            textField.stringValue = device.name
            textField.textColor = .labelColor
        case "mac":
            textField.stringValue = device.macAddress
            textField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            textField.textColor = .secondaryLabelColor
        case "last":
            if let date = device.lastUsed {
                let df = DateFormatter()
                df.dateStyle = .short
                df.timeStyle = .short
                var text = df.string(from: date)
                if let success = device.lastSuccess {
                    text += success ? " ✓" : " ✗"
                }
                textField.stringValue = text
                textField.textColor = .secondaryLabelColor
            } else {
                textField.stringValue = NSLocalizedString("wol.never", comment: "")
                textField.textColor = .tertiaryLabelColor
            }
        default:
            textField.stringValue = ""
        }

        return textField
    }
}

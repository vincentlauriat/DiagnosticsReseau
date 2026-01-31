// SettingsWindowController.swift
// Mon Réseau
//
// Fenêtre de réglages proposant six options :
//   1. Mode d'affichage : barre de menus ou application normale (AppMode)
//   2. Lancer l'app au démarrage de session (SMAppService.mainApp)
//   3. Notifications de changement de connexion (NotifyConnectionChange)
//   4. Afficher la latence dans la barre de menus (MenuBarShowLatency)
//   5. Apparence : Système / Clair / Sombre (AppAppearance)
//   6. Mode Geek : affiche/masque les outils techniques (GeekMode)
// Les préférences sont persistées dans UserDefaults et le système (Login Item).

import Cocoa
import ServiceManagement

class SettingsWindowController: NSWindowController {

    private var modePopup: NSPopUpButton!
    private var loginCheckbox: NSButton!
    private var notifyConnectionCheckbox: NSButton!
    private var menuBarLatencyCheckbox: NSButton!
    private var appearanceSegmented: NSSegmentedControl!
    private var geekModeCheckbox: NSButton!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("settings.title", comment: "")
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let appDelegate = NSApp.delegate as? AppDelegate
        let currentMode = appDelegate?.currentMode ?? .menubar

        // --- Mode d'affichage ---
        let modeLabel = NSTextField(labelWithString: NSLocalizedString("settings.mode.label", comment: ""))
        modeLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(modeLabel)

        modePopup = NSPopUpButton()
        modePopup.addItems(withTitles: [NSLocalizedString("settings.mode.menubar", comment: ""), NSLocalizedString("settings.mode.app", comment: "")])
        modePopup.translatesAutoresizingMaskIntoConstraints = false
        modePopup.target = self
        modePopup.action = #selector(modeChanged)
        modePopup.selectItem(at: currentMode == .menubar ? 0 : 1)
        contentView.addSubview(modePopup)

        let modeDesc = NSTextField(wrappingLabelWithString: NSLocalizedString("settings.mode.description", comment: ""))
        modeDesc.translatesAutoresizingMaskIntoConstraints = false
        modeDesc.font = NSFont.systemFont(ofSize: 11)
        modeDesc.textColor = .secondaryLabelColor
        modeDesc.isSelectable = false
        contentView.addSubview(modeDesc)

        // --- Separator ---
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator)

        // --- Lancer au demarrage ---
        loginCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("settings.login.title", comment: ""), target: self, action: #selector(loginCheckboxChanged))
        loginCheckbox.translatesAutoresizingMaskIntoConstraints = false
        loginCheckbox.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        contentView.addSubview(loginCheckbox)

        // Lire l'etat actuel du Login Item
        let loginStatus = SMAppService.mainApp.status
        loginCheckbox.state = (loginStatus == .enabled) ? .on : .off

        let loginDesc = NSTextField(wrappingLabelWithString: NSLocalizedString("settings.login.description", comment: ""))
        loginDesc.translatesAutoresizingMaskIntoConstraints = false
        loginDesc.font = NSFont.systemFont(ofSize: 11)
        loginDesc.textColor = .secondaryLabelColor
        loginDesc.isSelectable = false
        contentView.addSubview(loginDesc)

        // --- Separator 2 ---
        let separator2 = NSBox()
        separator2.boxType = .separator
        separator2.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator2)

        // --- Notifications ---
        notifyConnectionCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("settings.notify.title", comment: ""), target: self, action: #selector(notifyConnectionChanged))
        notifyConnectionCheckbox.translatesAutoresizingMaskIntoConstraints = false
        notifyConnectionCheckbox.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        notifyConnectionCheckbox.state = UserDefaults.standard.bool(forKey: "NotifyConnectionChange") ? .on : .off
        contentView.addSubview(notifyConnectionCheckbox)

        let notifyDesc = NSTextField(wrappingLabelWithString: NSLocalizedString("settings.notify.description", comment: ""))
        notifyDesc.translatesAutoresizingMaskIntoConstraints = false
        notifyDesc.font = NSFont.systemFont(ofSize: 11)
        notifyDesc.textColor = .secondaryLabelColor
        notifyDesc.isSelectable = false
        contentView.addSubview(notifyDesc)

        // --- Separator 3 ---
        let separator3 = NSBox()
        separator3.boxType = .separator
        separator3.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator3)

        // --- Latence barre de menus ---
        menuBarLatencyCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("settings.latency.title", comment: ""), target: self, action: #selector(menuBarLatencyChanged))
        menuBarLatencyCheckbox.translatesAutoresizingMaskIntoConstraints = false
        menuBarLatencyCheckbox.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        menuBarLatencyCheckbox.state = UserDefaults.standard.bool(forKey: "MenuBarShowLatency") ? .on : .off
        contentView.addSubview(menuBarLatencyCheckbox)

        let menuBarDesc = NSTextField(wrappingLabelWithString: NSLocalizedString("settings.latency.description", comment: ""))
        menuBarDesc.translatesAutoresizingMaskIntoConstraints = false
        menuBarDesc.font = NSFont.systemFont(ofSize: 11)
        menuBarDesc.textColor = .secondaryLabelColor
        menuBarDesc.isSelectable = false
        contentView.addSubview(menuBarDesc)

        // --- Separator 4 ---
        let separator4 = NSBox()
        separator4.boxType = .separator
        separator4.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator4)

        // --- Apparence ---
        let appearanceLabel = NSTextField(labelWithString: NSLocalizedString("settings.appearance.label", comment: ""))
        appearanceLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        appearanceLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(appearanceLabel)

        appearanceSegmented = NSSegmentedControl(labels: [NSLocalizedString("settings.appearance.system", comment: ""), NSLocalizedString("settings.appearance.light", comment: ""), NSLocalizedString("settings.appearance.dark", comment: "")], trackingMode: .selectOne, target: self, action: #selector(appearanceChanged))
        appearanceSegmented.translatesAutoresizingMaskIntoConstraints = false
        let saved = UserDefaults.standard.string(forKey: "AppAppearance") ?? "system"
        appearanceSegmented.selectedSegment = saved == "light" ? 1 : saved == "dark" ? 2 : 0
        contentView.addSubview(appearanceSegmented)

        let appearanceDesc = NSTextField(wrappingLabelWithString: NSLocalizedString("settings.appearance.description", comment: ""))
        appearanceDesc.translatesAutoresizingMaskIntoConstraints = false
        appearanceDesc.font = NSFont.systemFont(ofSize: 11)
        appearanceDesc.textColor = .secondaryLabelColor
        appearanceDesc.isSelectable = false
        contentView.addSubview(appearanceDesc)

        // --- Separator 5 ---
        let separator5 = NSBox()
        separator5.boxType = .separator
        separator5.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator5)

        // --- Mode Geek ---
        geekModeCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("settings.geek.title", comment: ""), target: self, action: #selector(geekModeChanged))
        geekModeCheckbox.translatesAutoresizingMaskIntoConstraints = false
        geekModeCheckbox.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        geekModeCheckbox.state = UserDefaults.standard.bool(forKey: "GeekMode") ? .on : .off
        contentView.addSubview(geekModeCheckbox)

        let geekDesc = NSTextField(wrappingLabelWithString: NSLocalizedString("settings.geek.description", comment: ""))
        geekDesc.translatesAutoresizingMaskIntoConstraints = false
        geekDesc.font = NSFont.systemFont(ofSize: 11)
        geekDesc.textColor = .secondaryLabelColor
        geekDesc.isSelectable = false
        contentView.addSubview(geekDesc)

        NSLayoutConstraint.activate([
            modeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            modeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),

            modePopup.centerYAnchor.constraint(equalTo: modeLabel.centerYAnchor),
            modePopup.leadingAnchor.constraint(equalTo: modeLabel.trailingAnchor, constant: 8),
            modePopup.widthAnchor.constraint(equalToConstant: 160),

            modeDesc.topAnchor.constraint(equalTo: modeLabel.bottomAnchor, constant: 8),
            modeDesc.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            modeDesc.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            separator.topAnchor.constraint(equalTo: modeDesc.bottomAnchor, constant: 16),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            loginCheckbox.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 16),
            loginCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            loginCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),

            loginDesc.topAnchor.constraint(equalTo: loginCheckbox.bottomAnchor, constant: 4),
            loginDesc.leadingAnchor.constraint(equalTo: loginCheckbox.leadingAnchor, constant: 18),
            loginDesc.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            separator2.topAnchor.constraint(equalTo: loginDesc.bottomAnchor, constant: 16),
            separator2.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            separator2.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            notifyConnectionCheckbox.topAnchor.constraint(equalTo: separator2.bottomAnchor, constant: 16),
            notifyConnectionCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            notifyConnectionCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),

            notifyDesc.topAnchor.constraint(equalTo: notifyConnectionCheckbox.bottomAnchor, constant: 4),
            notifyDesc.leadingAnchor.constraint(equalTo: notifyConnectionCheckbox.leadingAnchor, constant: 18),
            notifyDesc.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            separator3.topAnchor.constraint(equalTo: notifyDesc.bottomAnchor, constant: 16),
            separator3.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            separator3.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            menuBarLatencyCheckbox.topAnchor.constraint(equalTo: separator3.bottomAnchor, constant: 16),
            menuBarLatencyCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            menuBarLatencyCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),

            menuBarDesc.topAnchor.constraint(equalTo: menuBarLatencyCheckbox.bottomAnchor, constant: 4),
            menuBarDesc.leadingAnchor.constraint(equalTo: menuBarLatencyCheckbox.leadingAnchor, constant: 18),
            menuBarDesc.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            separator4.topAnchor.constraint(equalTo: menuBarDesc.bottomAnchor, constant: 16),
            separator4.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            separator4.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            appearanceLabel.topAnchor.constraint(equalTo: separator4.bottomAnchor, constant: 16),
            appearanceLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),

            appearanceSegmented.centerYAnchor.constraint(equalTo: appearanceLabel.centerYAnchor),
            appearanceSegmented.leadingAnchor.constraint(equalTo: appearanceLabel.trailingAnchor, constant: 8),

            appearanceDesc.topAnchor.constraint(equalTo: appearanceLabel.bottomAnchor, constant: 8),
            appearanceDesc.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            appearanceDesc.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            separator5.topAnchor.constraint(equalTo: appearanceDesc.bottomAnchor, constant: 16),
            separator5.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            separator5.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            geekModeCheckbox.topAnchor.constraint(equalTo: separator5.bottomAnchor, constant: 16),
            geekModeCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            geekModeCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),

            geekDesc.topAnchor.constraint(equalTo: geekModeCheckbox.bottomAnchor, constant: 4),
            geekDesc.leadingAnchor.constraint(equalTo: geekModeCheckbox.leadingAnchor, constant: 18),
            geekDesc.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            geekDesc.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
        ])
    }

    /// Bascule le mode d'affichage de l'application.
    @objc private func modeChanged(_ sender: NSPopUpButton) {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        let mode: AppDelegate.AppMode = sender.indexOfSelectedItem == 0 ? .menubar : .app
        appDelegate.applyMode(mode)
    }

    @objc private func notifyConnectionChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "NotifyConnectionChange")
    }

    @objc private func appearanceChanged(_ sender: NSSegmentedControl) {
        let mode: String
        switch sender.selectedSegment {
        case 1: mode = "light"
        case 2: mode = "dark"
        default: mode = "system"
        }
        UserDefaults.standard.set(mode, forKey: "AppAppearance")
        (NSApp.delegate as? AppDelegate)?.applyAppearance()
    }

    @objc private func geekModeChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "GeekMode")
        NotificationCenter.default.post(name: Notification.Name("GeekModeChanged"), object: nil)
    }

    @objc private func menuBarLatencyChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "MenuBarShowLatency")
        (NSApp.delegate as? AppDelegate)?.startMenuBarPingIfNeeded()
    }

    /// Enregistre ou désenregistre l'app comme Login Item via SMAppService (macOS 13+).
    @objc private func loginCheckboxChanged(_ sender: NSButton) {
        let enable = sender.state == .on
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // En cas d'erreur, remettre la checkbox a l'etat precedent
            sender.state = enable ? .off : .on
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("settings.login.error.title", comment: "")
            alert.informativeText = String(format: NSLocalizedString("settings.login.error.message", comment: ""), error.localizedDescription)
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            if let w = self.window { alert.beginSheetModal(for: w) }
        }
    }
}

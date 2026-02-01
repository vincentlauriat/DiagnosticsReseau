// SettingsWindowController.swift
// Mon Réseau
//
// Fenêtre de réglages avec onglets :
//   - Général : mode d'affichage, démarrage, apparence
//   - Notifications : connexion, qualité, speed test
//   - Avancé : barre de menus, cible ping, mode geek

import Cocoa
import ServiceManagement

class SettingsWindowController: NSWindowController {

    private var modePopup: NSPopUpButton!
    private var loginCheckbox: NSButton!
    private var notifyConnectionCheckbox: NSButton!
    private var notifyQualityCheckbox: NSButton!
    private var latencyThresholdField: NSTextField!
    private var lossThresholdField: NSTextField!
    private var notifySpeedTestCheckbox: NSButton!
    private var menuBarDisplayPopup: NSPopUpButton!
    private var pingTargetField: NSTextField!
    private var appearanceSegmented: NSSegmentedControl!
    private var geekModeCheckbox: NSButton!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
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

        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tabView)

        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])

        // Onglet 1 : Général
        let generalTab = NSTabViewItem(identifier: "general")
        generalTab.label = NSLocalizedString("settings.tab.general", comment: "")
        generalTab.view = buildGeneralTab()
        tabView.addTabViewItem(generalTab)

        // Onglet 2 : Notifications
        let notifTab = NSTabViewItem(identifier: "notifications")
        notifTab.label = NSLocalizedString("settings.tab.notifications", comment: "")
        notifTab.view = buildNotificationsTab()
        tabView.addTabViewItem(notifTab)

        // Onglet 3 : Avancé
        let advancedTab = NSTabViewItem(identifier: "advanced")
        advancedTab.label = NSLocalizedString("settings.tab.advanced", comment: "")
        advancedTab.view = buildAdvancedTab()
        tabView.addTabViewItem(advancedTab)
    }

    // MARK: - Onglet Général

    private func buildGeneralTab() -> NSView {
        let view = NSView()
        let m: CGFloat = 20
        let sp: CGFloat = 16
        let ssp: CGFloat = 4
        let di: CGFloat = 18

        let appDelegate = NSApp.delegate as? AppDelegate
        let currentMode = appDelegate?.currentMode ?? .menubar

        // Mode d'affichage
        let modeLabel = NSTextField(labelWithString: NSLocalizedString("settings.mode.label", comment: ""))
        modeLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(modeLabel)

        modePopup = NSPopUpButton()
        modePopup.addItems(withTitles: [NSLocalizedString("settings.mode.menubar", comment: ""), NSLocalizedString("settings.mode.app", comment: "")])
        modePopup.translatesAutoresizingMaskIntoConstraints = false
        modePopup.target = self
        modePopup.action = #selector(modeChanged)
        modePopup.selectItem(at: currentMode == .menubar ? 0 : 1)
        view.addSubview(modePopup)

        let modeDesc = NSTextField(wrappingLabelWithString: NSLocalizedString("settings.mode.description", comment: ""))
        modeDesc.translatesAutoresizingMaskIntoConstraints = false
        modeDesc.font = NSFont.systemFont(ofSize: 11)
        modeDesc.textColor = .secondaryLabelColor
        modeDesc.isSelectable = false
        view.addSubview(modeDesc)

        let sep1 = makeSeparator(in: view)

        // Lancer au démarrage
        loginCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("settings.login.title", comment: ""), target: self, action: #selector(loginCheckboxChanged))
        loginCheckbox.translatesAutoresizingMaskIntoConstraints = false
        loginCheckbox.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let loginStatus = SMAppService.mainApp.status
        loginCheckbox.state = (loginStatus == .enabled) ? .on : .off
        view.addSubview(loginCheckbox)

        let loginDesc = NSTextField(wrappingLabelWithString: NSLocalizedString("settings.login.description", comment: ""))
        loginDesc.translatesAutoresizingMaskIntoConstraints = false
        loginDesc.font = NSFont.systemFont(ofSize: 11)
        loginDesc.textColor = .secondaryLabelColor
        loginDesc.isSelectable = false
        view.addSubview(loginDesc)

        let sep2 = makeSeparator(in: view)

        // Apparence
        let appearanceLabel = NSTextField(labelWithString: NSLocalizedString("settings.appearance.label", comment: ""))
        appearanceLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        appearanceLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(appearanceLabel)

        appearanceSegmented = NSSegmentedControl(labels: [NSLocalizedString("settings.appearance.system", comment: ""), NSLocalizedString("settings.appearance.light", comment: ""), NSLocalizedString("settings.appearance.dark", comment: "")], trackingMode: .selectOne, target: self, action: #selector(appearanceChanged))
        appearanceSegmented.translatesAutoresizingMaskIntoConstraints = false
        let saved = UserDefaults.standard.string(forKey: "AppAppearance") ?? "system"
        appearanceSegmented.selectedSegment = saved == "light" ? 1 : saved == "dark" ? 2 : 0
        view.addSubview(appearanceSegmented)

        let appearanceDesc = NSTextField(wrappingLabelWithString: NSLocalizedString("settings.appearance.description", comment: ""))
        appearanceDesc.translatesAutoresizingMaskIntoConstraints = false
        appearanceDesc.font = NSFont.systemFont(ofSize: 11)
        appearanceDesc.textColor = .secondaryLabelColor
        appearanceDesc.isSelectable = false
        view.addSubview(appearanceDesc)

        NSLayoutConstraint.activate([
            modeLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: m),
            modeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            modePopup.centerYAnchor.constraint(equalTo: modeLabel.centerYAnchor),
            modePopup.leadingAnchor.constraint(equalTo: modeLabel.trailingAnchor, constant: 8),
            modePopup.widthAnchor.constraint(equalToConstant: 160),
            modeDesc.topAnchor.constraint(equalTo: modeLabel.bottomAnchor, constant: 8),
            modeDesc.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            modeDesc.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),

            sep1.topAnchor.constraint(equalTo: modeDesc.bottomAnchor, constant: sp),
            sep1.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            sep1.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),

            loginCheckbox.topAnchor.constraint(equalTo: sep1.bottomAnchor, constant: sp),
            loginCheckbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            loginCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -m),
            loginDesc.topAnchor.constraint(equalTo: loginCheckbox.bottomAnchor, constant: ssp),
            loginDesc.leadingAnchor.constraint(equalTo: loginCheckbox.leadingAnchor, constant: di),
            loginDesc.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),

            sep2.topAnchor.constraint(equalTo: loginDesc.bottomAnchor, constant: sp),
            sep2.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            sep2.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),

            appearanceLabel.topAnchor.constraint(equalTo: sep2.bottomAnchor, constant: sp),
            appearanceLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            appearanceSegmented.centerYAnchor.constraint(equalTo: appearanceLabel.centerYAnchor),
            appearanceSegmented.leadingAnchor.constraint(equalTo: appearanceLabel.trailingAnchor, constant: 8),
            appearanceDesc.topAnchor.constraint(equalTo: appearanceLabel.bottomAnchor, constant: 8),
            appearanceDesc.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            appearanceDesc.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),
        ])

        return view
    }

    // MARK: - Onglet Notifications

    private func buildNotificationsTab() -> NSView {
        let view = NSView()
        let m: CGFloat = 20
        let sp: CGFloat = 16
        let ssp: CGFloat = 4
        let di: CGFloat = 18

        // Notifications connexion
        notifyConnectionCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("settings.notify.title", comment: ""), target: self, action: #selector(notifyConnectionChanged))
        notifyConnectionCheckbox.translatesAutoresizingMaskIntoConstraints = false
        notifyConnectionCheckbox.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        notifyConnectionCheckbox.state = UserDefaults.standard.bool(forKey: "NotifyConnectionChange") ? .on : .off
        view.addSubview(notifyConnectionCheckbox)

        let notifyDesc = NSTextField(wrappingLabelWithString: NSLocalizedString("settings.notify.description", comment: ""))
        notifyDesc.translatesAutoresizingMaskIntoConstraints = false
        notifyDesc.font = NSFont.systemFont(ofSize: 11)
        notifyDesc.textColor = .secondaryLabelColor
        notifyDesc.isSelectable = false
        view.addSubview(notifyDesc)

        let sep1 = makeSeparator(in: view)

        // Notifications dégradation qualité
        notifyQualityCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("settings.notify_quality.title", comment: ""), target: self, action: #selector(notifyQualityChanged))
        notifyQualityCheckbox.translatesAutoresizingMaskIntoConstraints = false
        notifyQualityCheckbox.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        notifyQualityCheckbox.state = UserDefaults.standard.bool(forKey: "NotifyQualityDegradation") ? .on : .off
        view.addSubview(notifyQualityCheckbox)

        let latencyThresholdLabel = NSTextField(labelWithString: NSLocalizedString("settings.notify_quality.latency_threshold", comment: ""))
        latencyThresholdLabel.font = NSFont.systemFont(ofSize: 12)
        latencyThresholdLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(latencyThresholdLabel)

        latencyThresholdField = NSTextField()
        latencyThresholdField.translatesAutoresizingMaskIntoConstraints = false
        latencyThresholdField.placeholderString = "100"
        let savedLatThreshold = UserDefaults.standard.object(forKey: "NotifyLatencyThreshold") as? Double ?? 100
        latencyThresholdField.stringValue = String(format: "%.0f", savedLatThreshold)
        latencyThresholdField.formatter = NumberFormatter()
        latencyThresholdField.target = self
        latencyThresholdField.action = #selector(latencyThresholdChanged)
        view.addSubview(latencyThresholdField)

        let latencyUnitLabel = NSTextField(labelWithString: "ms")
        latencyUnitLabel.font = NSFont.systemFont(ofSize: 12)
        latencyUnitLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(latencyUnitLabel)

        let lossThresholdLabel = NSTextField(labelWithString: NSLocalizedString("settings.notify_quality.loss_threshold", comment: ""))
        lossThresholdLabel.font = NSFont.systemFont(ofSize: 12)
        lossThresholdLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(lossThresholdLabel)

        lossThresholdField = NSTextField()
        lossThresholdField.translatesAutoresizingMaskIntoConstraints = false
        lossThresholdField.placeholderString = "5"
        let savedLossThreshold = UserDefaults.standard.object(forKey: "NotifyLossThreshold") as? Double ?? 5
        lossThresholdField.stringValue = String(format: "%.0f", savedLossThreshold)
        lossThresholdField.formatter = NumberFormatter()
        lossThresholdField.target = self
        lossThresholdField.action = #selector(lossThresholdChanged)
        view.addSubview(lossThresholdField)

        let lossUnitLabel = NSTextField(labelWithString: "%")
        lossUnitLabel.font = NSFont.systemFont(ofSize: 12)
        lossUnitLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(lossUnitLabel)

        let sep2 = makeSeparator(in: view)

        // Notification fin speed test
        notifySpeedTestCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("settings.notify_speedtest.title", comment: ""), target: self, action: #selector(notifySpeedTestChanged))
        notifySpeedTestCheckbox.translatesAutoresizingMaskIntoConstraints = false
        notifySpeedTestCheckbox.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        notifySpeedTestCheckbox.state = UserDefaults.standard.bool(forKey: "NotifySpeedTestComplete") ? .on : .off
        view.addSubview(notifySpeedTestCheckbox)

        let notifySpeedTestDesc = NSTextField(wrappingLabelWithString: NSLocalizedString("settings.notify_speedtest.description", comment: ""))
        notifySpeedTestDesc.translatesAutoresizingMaskIntoConstraints = false
        notifySpeedTestDesc.font = NSFont.systemFont(ofSize: 11)
        notifySpeedTestDesc.textColor = .secondaryLabelColor
        notifySpeedTestDesc.isSelectable = false
        view.addSubview(notifySpeedTestDesc)

        NSLayoutConstraint.activate([
            notifyConnectionCheckbox.topAnchor.constraint(equalTo: view.topAnchor, constant: m),
            notifyConnectionCheckbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            notifyConnectionCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -m),
            notifyDesc.topAnchor.constraint(equalTo: notifyConnectionCheckbox.bottomAnchor, constant: ssp),
            notifyDesc.leadingAnchor.constraint(equalTo: notifyConnectionCheckbox.leadingAnchor, constant: di),
            notifyDesc.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),

            sep1.topAnchor.constraint(equalTo: notifyDesc.bottomAnchor, constant: sp),
            sep1.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            sep1.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),

            notifyQualityCheckbox.topAnchor.constraint(equalTo: sep1.bottomAnchor, constant: sp),
            notifyQualityCheckbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            notifyQualityCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -m),

            latencyThresholdLabel.topAnchor.constraint(equalTo: notifyQualityCheckbox.bottomAnchor, constant: 8),
            latencyThresholdLabel.leadingAnchor.constraint(equalTo: notifyQualityCheckbox.leadingAnchor, constant: di),
            latencyThresholdField.centerYAnchor.constraint(equalTo: latencyThresholdLabel.centerYAnchor),
            latencyThresholdField.leadingAnchor.constraint(equalTo: latencyThresholdLabel.trailingAnchor, constant: 8),
            latencyThresholdField.widthAnchor.constraint(equalToConstant: 60),
            latencyUnitLabel.centerYAnchor.constraint(equalTo: latencyThresholdField.centerYAnchor),
            latencyUnitLabel.leadingAnchor.constraint(equalTo: latencyThresholdField.trailingAnchor, constant: 4),

            lossThresholdLabel.topAnchor.constraint(equalTo: latencyThresholdLabel.bottomAnchor, constant: 6),
            lossThresholdLabel.leadingAnchor.constraint(equalTo: latencyThresholdLabel.leadingAnchor),
            lossThresholdField.centerYAnchor.constraint(equalTo: lossThresholdLabel.centerYAnchor),
            lossThresholdField.leadingAnchor.constraint(equalTo: lossThresholdLabel.trailingAnchor, constant: 8),
            lossThresholdField.widthAnchor.constraint(equalToConstant: 60),
            lossUnitLabel.centerYAnchor.constraint(equalTo: lossThresholdField.centerYAnchor),
            lossUnitLabel.leadingAnchor.constraint(equalTo: lossThresholdField.trailingAnchor, constant: 4),

            sep2.topAnchor.constraint(equalTo: lossThresholdLabel.bottomAnchor, constant: sp),
            sep2.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            sep2.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),

            notifySpeedTestCheckbox.topAnchor.constraint(equalTo: sep2.bottomAnchor, constant: sp),
            notifySpeedTestCheckbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            notifySpeedTestCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -m),
            notifySpeedTestDesc.topAnchor.constraint(equalTo: notifySpeedTestCheckbox.bottomAnchor, constant: ssp),
            notifySpeedTestDesc.leadingAnchor.constraint(equalTo: notifySpeedTestCheckbox.leadingAnchor, constant: di),
            notifySpeedTestDesc.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),
        ])

        return view
    }

    // MARK: - Onglet Avancé

    private func buildAdvancedTab() -> NSView {
        let view = NSView()
        let m: CGFloat = 20
        let sp: CGFloat = 16
        let ssp: CGFloat = 4
        let di: CGFloat = 18

        // Affichage barre de menus
        let menuBarLabel = NSTextField(labelWithString: NSLocalizedString("settings.menubar_display.label", comment: ""))
        menuBarLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        menuBarLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(menuBarLabel)

        menuBarDisplayPopup = NSPopUpButton()
        menuBarDisplayPopup.addItems(withTitles: [
            NSLocalizedString("settings.menubar_display.none", comment: ""),
            NSLocalizedString("settings.menubar_display.latency", comment: ""),
            NSLocalizedString("settings.menubar_display.throughput", comment: ""),
            NSLocalizedString("settings.menubar_display.rssi", comment: ""),
        ])
        menuBarDisplayPopup.translatesAutoresizingMaskIntoConstraints = false
        menuBarDisplayPopup.target = self
        menuBarDisplayPopup.action = #selector(menuBarDisplayChanged)
        let savedDisplayMode = UserDefaults.standard.string(forKey: "MenuBarDisplayMode") ?? (UserDefaults.standard.bool(forKey: "MenuBarShowLatency") ? "latency" : "none")
        switch savedDisplayMode {
        case "latency": menuBarDisplayPopup.selectItem(at: 1)
        case "throughput": menuBarDisplayPopup.selectItem(at: 2)
        case "rssi": menuBarDisplayPopup.selectItem(at: 3)
        default: menuBarDisplayPopup.selectItem(at: 0)
        }
        view.addSubview(menuBarDisplayPopup)

        let menuBarDesc = NSTextField(wrappingLabelWithString: NSLocalizedString("settings.menubar_display.description", comment: ""))
        menuBarDesc.translatesAutoresizingMaskIntoConstraints = false
        menuBarDesc.font = NSFont.systemFont(ofSize: 11)
        menuBarDesc.textColor = .secondaryLabelColor
        menuBarDesc.isSelectable = false
        view.addSubview(menuBarDesc)

        let sep1 = makeSeparator(in: view)

        // Cible ping
        let pingLabel = NSTextField(labelWithString: NSLocalizedString("settings.ping_target.label", comment: ""))
        pingLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        pingLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pingLabel)

        pingTargetField = NSTextField()
        pingTargetField.translatesAutoresizingMaskIntoConstraints = false
        pingTargetField.placeholderString = "8.8.8.8"
        pingTargetField.stringValue = UserDefaults.standard.string(forKey: "CustomPingTarget") ?? "8.8.8.8"
        pingTargetField.target = self
        pingTargetField.action = #selector(pingTargetChanged)
        view.addSubview(pingTargetField)

        let pingDesc = NSTextField(wrappingLabelWithString: NSLocalizedString("settings.ping_target.description", comment: ""))
        pingDesc.translatesAutoresizingMaskIntoConstraints = false
        pingDesc.font = NSFont.systemFont(ofSize: 11)
        pingDesc.textColor = .secondaryLabelColor
        pingDesc.isSelectable = false
        view.addSubview(pingDesc)

        let sep2 = makeSeparator(in: view)

        // Mode Geek
        geekModeCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("settings.geek.title", comment: ""), target: self, action: #selector(geekModeChanged))
        geekModeCheckbox.translatesAutoresizingMaskIntoConstraints = false
        geekModeCheckbox.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        geekModeCheckbox.state = UserDefaults.standard.bool(forKey: "GeekMode") ? .on : .off
        view.addSubview(geekModeCheckbox)

        let geekDesc = NSTextField(wrappingLabelWithString: NSLocalizedString("settings.geek.description", comment: ""))
        geekDesc.translatesAutoresizingMaskIntoConstraints = false
        geekDesc.font = NSFont.systemFont(ofSize: 11)
        geekDesc.textColor = .secondaryLabelColor
        geekDesc.isSelectable = false
        view.addSubview(geekDesc)

        NSLayoutConstraint.activate([
            menuBarLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: m),
            menuBarLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            menuBarDisplayPopup.centerYAnchor.constraint(equalTo: menuBarLabel.centerYAnchor),
            menuBarDisplayPopup.leadingAnchor.constraint(equalTo: menuBarLabel.trailingAnchor, constant: 8),
            menuBarDisplayPopup.widthAnchor.constraint(equalToConstant: 160),
            menuBarDesc.topAnchor.constraint(equalTo: menuBarLabel.bottomAnchor, constant: 8),
            menuBarDesc.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            menuBarDesc.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),

            sep1.topAnchor.constraint(equalTo: menuBarDesc.bottomAnchor, constant: sp),
            sep1.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            sep1.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),

            pingLabel.topAnchor.constraint(equalTo: sep1.bottomAnchor, constant: sp),
            pingLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            pingTargetField.centerYAnchor.constraint(equalTo: pingLabel.centerYAnchor),
            pingTargetField.leadingAnchor.constraint(equalTo: pingLabel.trailingAnchor, constant: 8),
            pingTargetField.widthAnchor.constraint(equalToConstant: 160),
            pingDesc.topAnchor.constraint(equalTo: pingLabel.bottomAnchor, constant: 8),
            pingDesc.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            pingDesc.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),

            sep2.topAnchor.constraint(equalTo: pingDesc.bottomAnchor, constant: sp),
            sep2.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            sep2.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),

            geekModeCheckbox.topAnchor.constraint(equalTo: sep2.bottomAnchor, constant: sp),
            geekModeCheckbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            geekModeCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -m),
            geekDesc.topAnchor.constraint(equalTo: geekModeCheckbox.bottomAnchor, constant: ssp),
            geekDesc.leadingAnchor.constraint(equalTo: geekModeCheckbox.leadingAnchor, constant: di),
            geekDesc.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),
        ])

        return view
    }

    // MARK: - Helpers

    private func makeSeparator(in parent: NSView) -> NSBox {
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(sep)
        return sep
    }

    // MARK: - Actions

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        let mode: AppDelegate.AppMode = sender.indexOfSelectedItem == 0 ? .menubar : .app
        appDelegate.applyMode(mode)
    }

    @objc private func loginCheckboxChanged(_ sender: NSButton) {
        let enable = sender.state == .on
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            sender.state = enable ? .off : .on
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("settings.login.error.title", comment: "")
            alert.informativeText = String(format: NSLocalizedString("settings.login.error.message", comment: ""), error.localizedDescription)
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            if let w = self.window { alert.beginSheetModal(for: w) }
        }
    }

    @objc private func notifyConnectionChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "NotifyConnectionChange")
    }

    @objc private func notifyQualityChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "NotifyQualityDegradation")
    }

    @objc private func latencyThresholdChanged(_ sender: NSTextField) {
        let value = sender.doubleValue
        UserDefaults.standard.set(value > 0 ? value : 100, forKey: "NotifyLatencyThreshold")
    }

    @objc private func lossThresholdChanged(_ sender: NSTextField) {
        let value = sender.doubleValue
        UserDefaults.standard.set(value > 0 ? value : 5, forKey: "NotifyLossThreshold")
    }

    @objc private func notifySpeedTestChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "NotifySpeedTestComplete")
    }

    @objc private func menuBarDisplayChanged(_ sender: NSPopUpButton) {
        let modes = ["none", "latency", "throughput", "rssi"]
        let mode = modes[sender.indexOfSelectedItem]
        UserDefaults.standard.set(mode, forKey: "MenuBarDisplayMode")
        UserDefaults.standard.set(mode == "latency", forKey: "MenuBarShowLatency")
        (NSApp.delegate as? AppDelegate)?.startMenuBarPingIfNeeded()
    }

    @objc private func pingTargetChanged(_ sender: NSTextField) {
        let target = sender.stringValue.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(target.isEmpty ? "8.8.8.8" : target, forKey: "CustomPingTarget")
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
}

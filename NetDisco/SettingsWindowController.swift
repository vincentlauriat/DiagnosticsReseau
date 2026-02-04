// SettingsWindowController.swift
// NetDisco
//
// Fenêtre de réglages avec onglets :
//   - Général : mode d'affichage, démarrage, apparence
//   - Notifications : connexion, qualité, speed test
//   - Avancé : barre de menus, cible ping, mode geek

import Cocoa
import ServiceManagement
import CoreWLAN

// MARK: - Network Profiles

struct PerformanceSnapshot: Codable {
    let date: Date
    let avgLatency: Double?
    let downloadMbps: Double?
    let uploadMbps: Double?
}

struct NetworkProfile: Codable {
    let id: UUID
    var name: String
    let ssid: String
    let createdDate: Date
    var lastConnected: Date?
    var performanceSnapshots: [PerformanceSnapshot]

    init(name: String, ssid: String) {
        self.id = UUID()
        self.name = name
        self.ssid = ssid
        self.createdDate = Date()
        self.lastConnected = Date()
        self.performanceSnapshots = []
    }
}

class NetworkProfileStorage {
    private static let key = "NetworkProfiles"
    private static let maxProfiles = 30
    private static let maxSnapshots = 100

    static func load() -> [NetworkProfile] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let profiles = try? JSONDecoder().decode([NetworkProfile].self, from: data) else {
            return []
        }
        return profiles
    }

    static func save(_ profiles: [NetworkProfile]) {
        var trimmed = Array(profiles.prefix(maxProfiles))
        // Trim snapshots per profile
        for i in trimmed.indices {
            if trimmed[i].performanceSnapshots.count > maxSnapshots {
                trimmed[i].performanceSnapshots = Array(trimmed[i].performanceSnapshots.suffix(maxSnapshots))
            }
        }
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func add(_ profile: NetworkProfile) {
        var profiles = load()
        profiles.insert(profile, at: 0)
        save(profiles)
    }

    static func remove(id: UUID) {
        var profiles = load()
        profiles.removeAll { $0.id == id }
        save(profiles)
    }

    static func profileForSSID(_ ssid: String) -> NetworkProfile? {
        return load().first { $0.ssid == ssid }
    }

    static func updateLastConnected(ssid: String) {
        var profiles = load()
        if let idx = profiles.firstIndex(where: { $0.ssid == ssid }) {
            profiles[idx].lastConnected = Date()
            save(profiles)
        }
    }

    static func addSnapshot(ssid: String, snapshot: PerformanceSnapshot) {
        var profiles = load()
        if let idx = profiles.firstIndex(where: { $0.ssid == ssid }) {
            profiles[idx].performanceSnapshots.append(snapshot)
            save(profiles)
        }
    }

    static func rename(id: UUID, name: String) {
        var profiles = load()
        if let idx = profiles.firstIndex(where: { $0.id == id }) {
            profiles[idx].name = name
            save(profiles)
        }
    }
}

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
    private var iCloudSyncCheckbox: NSButton!
    private var profilesTableView: NSTableView?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 480),
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

        // Onglet 4 : Profils réseau
        let profilesTab = NSTabViewItem(identifier: "profiles")
        profilesTab.label = NSLocalizedString("settings.tab.profiles", comment: "")
        profilesTab.view = buildProfilesTab()
        tabView.addTabViewItem(profilesTab)
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
        let containerView = NSView()

        // Créer un scroll view pour gérer le contenu
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        containerView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        // Document view (contenu scrollable)
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = view

        let m: CGFloat = 16
        let sp: CGFloat = 12
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

        // Conteneur horizontal pour les seuils (plus compact)
        let thresholdsStack = NSStackView()
        thresholdsStack.orientation = .horizontal
        thresholdsStack.spacing = 20
        thresholdsStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(thresholdsStack)

        // Seuil latence
        let latencyStack = NSStackView()
        latencyStack.orientation = .horizontal
        latencyStack.spacing = 4

        let latencyThresholdLabel = NSTextField(labelWithString: NSLocalizedString("settings.notify_quality.latency_threshold", comment: ""))
        latencyThresholdLabel.font = NSFont.systemFont(ofSize: 11)
        latencyStack.addArrangedSubview(latencyThresholdLabel)

        latencyThresholdField = NSTextField()
        latencyThresholdField.placeholderString = "100"
        let savedLatThreshold = UserDefaults.standard.object(forKey: "NotifyLatencyThreshold") as? Double ?? 100
        latencyThresholdField.stringValue = String(format: "%.0f", savedLatThreshold)
        latencyThresholdField.formatter = NumberFormatter()
        latencyThresholdField.target = self
        latencyThresholdField.action = #selector(latencyThresholdChanged)
        latencyThresholdField.widthAnchor.constraint(equalToConstant: 50).isActive = true
        latencyStack.addArrangedSubview(latencyThresholdField)

        let latencyUnitLabel = NSTextField(labelWithString: "ms")
        latencyUnitLabel.font = NSFont.systemFont(ofSize: 11)
        latencyStack.addArrangedSubview(latencyUnitLabel)

        thresholdsStack.addArrangedSubview(latencyStack)

        // Seuil perte
        let lossStack = NSStackView()
        lossStack.orientation = .horizontal
        lossStack.spacing = 4

        let lossThresholdLabel = NSTextField(labelWithString: NSLocalizedString("settings.notify_quality.loss_threshold", comment: ""))
        lossThresholdLabel.font = NSFont.systemFont(ofSize: 11)
        lossStack.addArrangedSubview(lossThresholdLabel)

        lossThresholdField = NSTextField()
        lossThresholdField.placeholderString = "5"
        let savedLossThreshold = UserDefaults.standard.object(forKey: "NotifyLossThreshold") as? Double ?? 5
        lossThresholdField.stringValue = String(format: "%.0f", savedLossThreshold)
        lossThresholdField.formatter = NumberFormatter()
        lossThresholdField.target = self
        lossThresholdField.action = #selector(lossThresholdChanged)
        lossThresholdField.widthAnchor.constraint(equalToConstant: 50).isActive = true
        lossStack.addArrangedSubview(lossThresholdField)

        let lossUnitLabel = NSTextField(labelWithString: "%")
        lossUnitLabel.font = NSFont.systemFont(ofSize: 11)
        lossStack.addArrangedSubview(lossUnitLabel)

        thresholdsStack.addArrangedSubview(lossStack)

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

        let sep3 = makeSeparator(in: view)

        // Tests planifiés
        let scheduledTitle = NSTextField(labelWithString: NSLocalizedString("scheduled.section.title", comment: ""))
        scheduledTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        scheduledTitle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scheduledTitle)

        let scheduledEnableCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("scheduled.enable", comment: ""), target: self, action: #selector(scheduledEnableChanged))
        scheduledEnableCheckbox.translatesAutoresizingMaskIntoConstraints = false
        scheduledEnableCheckbox.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        scheduledEnableCheckbox.state = UserDefaults.standard.bool(forKey: "ScheduledQualityTestEnabled") ? .on : .off
        view.addSubview(scheduledEnableCheckbox)

        // Intervalle sur la même ligne
        let intervalStack = NSStackView()
        intervalStack.orientation = .horizontal
        intervalStack.spacing = 8
        intervalStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(intervalStack)

        let scheduledIntervalLabel = NSTextField(labelWithString: NSLocalizedString("scheduled.interval", comment: ""))
        scheduledIntervalLabel.font = NSFont.systemFont(ofSize: 11)
        intervalStack.addArrangedSubview(scheduledIntervalLabel)

        let scheduledIntervalPopup = NSPopUpButton()
        scheduledIntervalPopup.addItems(withTitles: [
            NSLocalizedString("scheduled.interval.5", comment: ""),
            NSLocalizedString("scheduled.interval.15", comment: ""),
            NSLocalizedString("scheduled.interval.30", comment: ""),
            NSLocalizedString("scheduled.interval.60", comment: ""),
        ])
        scheduledIntervalPopup.target = self
        scheduledIntervalPopup.action = #selector(scheduledIntervalChanged)
        let savedInterval = UserDefaults.standard.integer(forKey: "ScheduledQualityTestInterval")
        switch savedInterval {
        case 15: scheduledIntervalPopup.selectItem(at: 1)
        case 30: scheduledIntervalPopup.selectItem(at: 2)
        case 60: scheduledIntervalPopup.selectItem(at: 3)
        default: scheduledIntervalPopup.selectItem(at: 0)
        }
        intervalStack.addArrangedSubview(scheduledIntervalPopup)

        let scheduledDailyCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("scheduled.daily.enable", comment: ""), target: self, action: #selector(scheduledDailyChanged))
        scheduledDailyCheckbox.translatesAutoresizingMaskIntoConstraints = false
        scheduledDailyCheckbox.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        scheduledDailyCheckbox.state = UserDefaults.standard.bool(forKey: "ScheduledDailyNotification") ? .on : .off
        view.addSubview(scheduledDailyCheckbox)

        // Contraintes pour le document view
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            view.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

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

            thresholdsStack.topAnchor.constraint(equalTo: notifyQualityCheckbox.bottomAnchor, constant: 6),
            thresholdsStack.leadingAnchor.constraint(equalTo: notifyQualityCheckbox.leadingAnchor, constant: di),

            sep2.topAnchor.constraint(equalTo: thresholdsStack.bottomAnchor, constant: sp),
            sep2.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            sep2.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),

            notifySpeedTestCheckbox.topAnchor.constraint(equalTo: sep2.bottomAnchor, constant: sp),
            notifySpeedTestCheckbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            notifySpeedTestCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -m),
            notifySpeedTestDesc.topAnchor.constraint(equalTo: notifySpeedTestCheckbox.bottomAnchor, constant: ssp),
            notifySpeedTestDesc.leadingAnchor.constraint(equalTo: notifySpeedTestCheckbox.leadingAnchor, constant: di),
            notifySpeedTestDesc.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),

            sep3.topAnchor.constraint(equalTo: notifySpeedTestDesc.bottomAnchor, constant: sp),
            sep3.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            sep3.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),

            scheduledTitle.topAnchor.constraint(equalTo: sep3.bottomAnchor, constant: sp),
            scheduledTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),

            scheduledEnableCheckbox.topAnchor.constraint(equalTo: scheduledTitle.bottomAnchor, constant: 6),
            scheduledEnableCheckbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),

            intervalStack.topAnchor.constraint(equalTo: scheduledEnableCheckbox.bottomAnchor, constant: 6),
            intervalStack.leadingAnchor.constraint(equalTo: scheduledEnableCheckbox.leadingAnchor, constant: di),

            scheduledDailyCheckbox.topAnchor.constraint(equalTo: intervalStack.bottomAnchor, constant: 6),
            scheduledDailyCheckbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            scheduledDailyCheckbox.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -m),
        ])

        return containerView
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

        let sep3 = makeSeparator(in: view)

        // Synchronisation iCloud
        iCloudSyncCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("settings.icloud.title", comment: ""), target: self, action: #selector(iCloudSyncChanged))
        iCloudSyncCheckbox.translatesAutoresizingMaskIntoConstraints = false
        iCloudSyncCheckbox.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        iCloudSyncCheckbox.state = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") ? .on : .off
        view.addSubview(iCloudSyncCheckbox)

        let iCloudDesc = NSTextField(wrappingLabelWithString: NSLocalizedString("settings.icloud.description", comment: ""))
        iCloudDesc.translatesAutoresizingMaskIntoConstraints = false
        iCloudDesc.font = NSFont.systemFont(ofSize: 11)
        iCloudDesc.textColor = .secondaryLabelColor
        iCloudDesc.isSelectable = false
        view.addSubview(iCloudDesc)

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

            sep3.topAnchor.constraint(equalTo: geekDesc.bottomAnchor, constant: sp),
            sep3.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            sep3.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),

            iCloudSyncCheckbox.topAnchor.constraint(equalTo: sep3.bottomAnchor, constant: sp),
            iCloudSyncCheckbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            iCloudSyncCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -m),
            iCloudDesc.topAnchor.constraint(equalTo: iCloudSyncCheckbox.bottomAnchor, constant: ssp),
            iCloudDesc.leadingAnchor.constraint(equalTo: iCloudSyncCheckbox.leadingAnchor, constant: di),
            iCloudDesc.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),
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

    @objc private func scheduledEnableChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "ScheduledQualityTestEnabled")
        (NSApp.delegate as? AppDelegate)?.startScheduledTestsIfNeeded()
    }

    @objc private func scheduledIntervalChanged(_ sender: NSPopUpButton) {
        let values = [5, 15, 30, 60]
        let interval = values[sender.indexOfSelectedItem]
        UserDefaults.standard.set(interval, forKey: "ScheduledQualityTestInterval")
        (NSApp.delegate as? AppDelegate)?.startScheduledTestsIfNeeded()
    }

    @objc private func scheduledDailyChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "ScheduledDailyNotification")
    }

    @objc private func geekModeChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "GeekMode")
        NotificationCenter.default.post(name: Notification.Name("GeekModeChanged"), object: nil)
    }

    @objc private func iCloudSyncChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: "iCloudSyncEnabled")
        if enabled {
            iCloudSyncManager.shared.startSync()
            iCloudSyncManager.shared.uploadToCloud()
        } else {
            iCloudSyncManager.shared.stopSync()
        }
    }

    // MARK: - Onglet Profils réseau

    private func buildProfilesTab() -> NSView {
        let view = NSView()
        let m: CGFloat = 20

        let titleLabel = NSTextField(labelWithString: NSLocalizedString("settings.profiles.title", comment: ""))
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        let descLabel = NSTextField(wrappingLabelWithString: NSLocalizedString("settings.profiles.description", comment: ""))
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        descLabel.isSelectable = false
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(descLabel)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        view.addSubview(scrollView)

        let tableView = NSTableView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 22
        tableView.usesAlternatingRowBackgroundColors = true

        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("profileName"))
        nameCol.title = NSLocalizedString("settings.profiles.column.name", comment: "")
        nameCol.width = 100
        tableView.addTableColumn(nameCol)

        let ssidCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("profileSSID"))
        ssidCol.title = NSLocalizedString("settings.profiles.column.ssid", comment: "")
        ssidCol.width = 100
        tableView.addTableColumn(ssidCol)

        let lastCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("profileLastConnected"))
        lastCol.title = NSLocalizedString("settings.profiles.column.lastconnected", comment: "")
        lastCol.width = 120
        tableView.addTableColumn(lastCol)

        let testsCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("profileTests"))
        testsCol.title = NSLocalizedString("settings.profiles.column.tests", comment: "")
        testsCol.width = 50
        tableView.addTableColumn(testsCol)

        scrollView.documentView = tableView
        self.profilesTableView = tableView

        let buttonBar = NSStackView()
        buttonBar.orientation = .horizontal
        buttonBar.spacing = 8
        buttonBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttonBar)

        let addButton = NSButton(title: NSLocalizedString("settings.profiles.button.add", comment: ""), target: self, action: #selector(addCurrentNetwork))
        addButton.bezelStyle = .rounded
        buttonBar.addArrangedSubview(addButton)

        let renameButton = NSButton(title: NSLocalizedString("settings.profiles.button.rename", comment: ""), target: self, action: #selector(renameSelectedProfile))
        renameButton.bezelStyle = .rounded
        buttonBar.addArrangedSubview(renameButton)

        let deleteButton = NSButton(title: NSLocalizedString("settings.profiles.button.delete", comment: ""), target: self, action: #selector(deleteSelectedProfile))
        deleteButton.bezelStyle = .rounded
        buttonBar.addArrangedSubview(deleteButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: m),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            descLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            descLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),
            scrollView.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),
            scrollView.bottomAnchor.constraint(equalTo: buttonBar.topAnchor, constant: -8),
            buttonBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            buttonBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -m),
        ])

        return view
    }

    @objc private func addCurrentNetwork() {
        guard let ssid = CWWiFiClient.shared().interface()?.ssid(), !ssid.isEmpty else {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("settings.profiles.no_wifi", comment: "")
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            if let w = self.window { alert.beginSheetModal(for: w) }
            return
        }

        if NetworkProfileStorage.profileForSSID(ssid) != nil {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("settings.profiles.already_exists", comment: "")
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            if let w = self.window { alert.beginSheetModal(for: w) }
            return
        }

        let profile = NetworkProfile(name: ssid, ssid: ssid)
        NetworkProfileStorage.add(profile)
        profilesTableView?.reloadData()
    }

    @objc private func renameSelectedProfile() {
        guard let tableView = profilesTableView else { return }
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        let profiles = NetworkProfileStorage.load()
        guard row < profiles.count else { return }
        let profile = profiles[row]

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("settings.profiles.rename.title", comment: "")
        alert.informativeText = String(format: NSLocalizedString("settings.profiles.rename.message", comment: ""), profile.name)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: NSLocalizedString("speedtest.clear.confirm_cancel", comment: ""))

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = profile.name
        alert.accessoryView = input

        if let w = self.window {
            alert.beginSheetModal(for: w) { response in
                if response == .alertFirstButtonReturn {
                    let newName = input.stringValue.trimmingCharacters(in: .whitespaces)
                    if !newName.isEmpty {
                        NetworkProfileStorage.rename(id: profile.id, name: newName)
                        tableView.reloadData()
                    }
                }
            }
        }
    }

    @objc private func deleteSelectedProfile() {
        guard let tableView = profilesTableView else { return }
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        let profiles = NetworkProfileStorage.load()
        guard row < profiles.count else { return }
        NetworkProfileStorage.remove(id: profiles[row].id)
        tableView.reloadData()
    }
}

// MARK: - NSTableViewDataSource & NSTableViewDelegate (Profils)

extension SettingsWindowController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return NetworkProfileStorage.load().count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let profiles = NetworkProfileStorage.load()
        guard row < profiles.count else { return nil }
        let profile = profiles[row]

        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("")
        let cellIdentifier = NSUserInterfaceItemIdentifier("ProfileCell_\(identifier.rawValue)")

        let textField: NSTextField
        if let existing = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTextField {
            textField = existing
        } else {
            textField = NSTextField(labelWithString: "")
            textField.identifier = cellIdentifier
            textField.font = NSFont.systemFont(ofSize: 11)
        }

        let df: DateFormatter = {
            let f = DateFormatter()
            f.dateStyle = .short
            f.timeStyle = .short
            return f
        }()

        switch identifier.rawValue {
        case "profileName":
            textField.stringValue = profile.name
        case "profileSSID":
            textField.stringValue = profile.ssid
        case "profileLastConnected":
            if let date = profile.lastConnected {
                textField.stringValue = df.string(from: date)
            } else {
                textField.stringValue = "—"
            }
        case "profileTests":
            textField.stringValue = "\(profile.performanceSnapshots.count)"
        default:
            textField.stringValue = ""
        }

        return textField
    }
}

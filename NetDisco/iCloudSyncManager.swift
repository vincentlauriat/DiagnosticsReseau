// iCloudSyncManager.swift
// NetDisco — Synchronisation iCloud via NSUbiquitousKeyValueStore
// Synchronise l'historique des tests, favoris et profils réseau entre appareils

import Foundation

// MARK: - iCloud Sync Manager

class iCloudSyncManager {
    static let shared = iCloudSyncManager()

    private let cloudStore = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard

    // Clés synchronisées
    private let syncKeys = [
        "SpeedTestHistory",
        "QualityHistory",
        "QueryFavorites",
        "NetworkProfiles",
        "CustomPingTarget",
        "GeekMode",
        "AppAppearance",
        "MenuBarDisplayMode",
        "NotifyConnectionChange",
        "NotifyQualityDegradation",
        "NotifyLatencyThreshold",
        "NotifyLossThreshold",
        "NotifySpeedTestComplete",
        "ScheduledQualityTestEnabled",
        "ScheduledQualityTestInterval",
        "ScheduledDailyNotification"
    ]

    // Notification pour informer l'app des changements
    static let didSyncNotification = Notification.Name("iCloudSyncManagerDidSync")

    private var isObserving = false
    private var isAvailable = false

    private init() {}

    // MARK: - Availability Check

    private func checkiCloudAvailability() -> Bool {
        // Vérifier si l'utilisateur est connecté à iCloud
        guard FileManager.default.ubiquityIdentityToken != nil else {
            print("[iCloud] Utilisateur non connecté à iCloud")
            return false
        }
        return true
    }

    // MARK: - Setup

    func startSync() {
        guard !isObserving else { return }

        // Vérifier si iCloud est disponible
        isAvailable = checkiCloudAvailability()
        guard isAvailable else {
            print("[iCloud] Synchronisation désactivée (iCloud non disponible)")
            return
        }

        isObserving = true

        // Observer les changements iCloud
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudStoreDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore
        )

        // Synchroniser immédiatement
        let success = cloudStore.synchronize()
        if !success {
            print("[iCloud] Synchronisation initiale échouée")
            isAvailable = false
            return
        }

        // Télécharger les données cloud existantes
        downloadFromCloud()

        print("[iCloud] Synchronisation démarrée")
    }

    func stopSync() {
        guard isObserving else { return }
        isObserving = false

        NotificationCenter.default.removeObserver(
            self,
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore
        )

        print("[iCloud] Synchronisation arrêtée")
    }

    // MARK: - Upload to iCloud

    func uploadToCloud() {
        guard isAvailable else { return }
        for key in syncKeys {
            if let value = defaults.object(forKey: key) {
                cloudStore.set(value, forKey: key)
            }
        }
        cloudStore.synchronize()
        print("[iCloud] Données uploadées vers iCloud")
    }

    func uploadKey(_ key: String) {
        guard isAvailable, syncKeys.contains(key) else { return }
        if let value = defaults.object(forKey: key) {
            cloudStore.set(value, forKey: key)
            cloudStore.synchronize()
        }
    }

    // MARK: - Download from iCloud

    private func downloadFromCloud() {
        var hasChanges = false

        for key in syncKeys {
            if let cloudValue = cloudStore.object(forKey: key) {
                // Fusionner les historiques plutôt que remplacer
                if key == "SpeedTestHistory" {
                    mergeSpeedTestHistory(cloudValue)
                    hasChanges = true
                } else if key == "QualityHistory" {
                    mergeQualityHistory(cloudValue)
                    hasChanges = true
                } else if key == "QueryFavorites" {
                    mergeFavorites(cloudValue)
                    hasChanges = true
                } else if key == "NetworkProfiles" {
                    mergeNetworkProfiles(cloudValue)
                    hasChanges = true
                } else {
                    // Pour les autres clés, prendre la valeur cloud
                    defaults.set(cloudValue, forKey: key)
                    hasChanges = true
                }
            }
        }

        if hasChanges {
            NotificationCenter.default.post(name: Self.didSyncNotification, object: nil)
            print("[iCloud] Données téléchargées depuis iCloud")
        }
    }

    // MARK: - Merge Strategies

    private func mergeSpeedTestHistory(_ cloudValue: Any) {
        guard let cloudData = cloudValue as? Data else { return }

        // Structure locale pour décoder (doit correspondre à la structure dans SpeedTestWindowController)
        struct SpeedEntry: Codable {
            let date: Date
            let download: Double
            let upload: Double
            let latency: Double
            let location: String?
        }

        let decoder = JSONDecoder()
        guard let cloudHistory = try? decoder.decode([SpeedEntry].self, from: cloudData) else { return }

        // Charger l'historique local
        var localHistory: [SpeedEntry] = []
        if let localData = defaults.data(forKey: "SpeedTestHistory"),
           let decoded = try? decoder.decode([SpeedEntry].self, from: localData) {
            localHistory = decoded
        }

        // Fusionner en évitant les doublons (basé sur la date)
        var merged = localHistory
        let localDates = Set(localHistory.map { $0.date.timeIntervalSince1970 })

        for entry in cloudHistory {
            if !localDates.contains(entry.date.timeIntervalSince1970) {
                merged.append(entry)
            }
        }

        // Trier par date et limiter à 50 entrées
        merged.sort { $0.date > $1.date }
        if merged.count > 50 {
            merged = Array(merged.prefix(50))
        }

        // Sauvegarder
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(merged) {
            defaults.set(data, forKey: "SpeedTestHistory")
        }
    }

    private func mergeQualityHistory(_ cloudValue: Any) {
        guard let cloudData = cloudValue as? Data else { return }

        struct QualityEntry: Codable {
            let date: Date
            let latency: Double
            let jitter: Double
            let packetLoss: Double
        }

        let decoder = JSONDecoder()
        guard let cloudHistory = try? decoder.decode([QualityEntry].self, from: cloudData) else { return }

        var localHistory: [QualityEntry] = []
        if let localData = defaults.data(forKey: "QualityHistory"),
           let decoded = try? decoder.decode([QualityEntry].self, from: localData) {
            localHistory = decoded
        }

        // Fusionner
        var merged = localHistory
        let localDates = Set(localHistory.map { $0.date.timeIntervalSince1970 })

        for entry in cloudHistory {
            if !localDates.contains(entry.date.timeIntervalSince1970) {
                merged.append(entry)
            }
        }

        // Trier et limiter à 2880 entrées (24h avec intervalles de 30s)
        merged.sort { $0.date > $1.date }
        if merged.count > 2880 {
            merged = Array(merged.prefix(2880))
        }

        let encoder = JSONEncoder()
        if let data = try? encoder.encode(merged) {
            defaults.set(data, forKey: "QualityHistory")
        }
    }

    private func mergeFavorites(_ cloudValue: Any) {
        guard let cloudData = cloudValue as? Data else { return }

        struct Favorite: Codable {
            let type: String
            let value: String
            let label: String?
        }

        let decoder = JSONDecoder()
        guard let cloudFavorites = try? decoder.decode([Favorite].self, from: cloudData) else { return }

        var localFavorites: [Favorite] = []
        if let localData = defaults.data(forKey: "QueryFavorites"),
           let decoded = try? decoder.decode([Favorite].self, from: localData) {
            localFavorites = decoded
        }

        // Fusionner en évitant les doublons (basé sur la valeur)
        var merged = localFavorites
        let localValues = Set(localFavorites.map { $0.value })

        for fav in cloudFavorites {
            if !localValues.contains(fav.value) {
                merged.append(fav)
            }
        }

        // Limiter à 20 favoris
        if merged.count > 20 {
            merged = Array(merged.prefix(20))
        }

        let encoder = JSONEncoder()
        if let data = try? encoder.encode(merged) {
            defaults.set(data, forKey: "QueryFavorites")
        }
    }

    private func mergeNetworkProfiles(_ cloudValue: Any) {
        guard let cloudData = cloudValue as? Data else { return }

        struct Profile: Codable {
            let ssid: String
            let lastSeen: Date
            let avgDownload: Double?
            let avgUpload: Double?
            let avgLatency: Double?
            let testCount: Int
        }

        let decoder = JSONDecoder()
        guard let cloudProfiles = try? decoder.decode([Profile].self, from: cloudData) else { return }

        var localProfiles: [Profile] = []
        if let localData = defaults.data(forKey: "NetworkProfiles"),
           let decoded = try? decoder.decode([Profile].self, from: localData) {
            localProfiles = decoded
        }

        // Fusionner par SSID (prendre le plus récent)
        var profilesBySSID: [String: Profile] = [:]

        for profile in localProfiles {
            profilesBySSID[profile.ssid] = profile
        }

        for profile in cloudProfiles {
            if let existing = profilesBySSID[profile.ssid] {
                if profile.lastSeen > existing.lastSeen {
                    profilesBySSID[profile.ssid] = profile
                }
            } else {
                profilesBySSID[profile.ssid] = profile
            }
        }

        var merged = Array(profilesBySSID.values)
        merged.sort { $0.lastSeen > $1.lastSeen }

        // Limiter à 30 profils
        if merged.count > 30 {
            merged = Array(merged.prefix(30))
        }

        let encoder = JSONEncoder()
        if let data = try? encoder.encode(merged) {
            defaults.set(data, forKey: "NetworkProfiles")
        }
    }

    // MARK: - Cloud Change Handler

    @objc private func cloudStoreDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonNumber = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }

        // Constantes de raison de changement
        let serverChange = NSUbiquitousKeyValueStoreServerChange
        let initialSyncChange = NSUbiquitousKeyValueStoreInitialSyncChange
        let quotaViolationChange = NSUbiquitousKeyValueStoreQuotaViolationChange
        let accountChange = NSUbiquitousKeyValueStoreAccountChange

        switch reasonNumber {
        case serverChange, initialSyncChange:
            // Changements depuis un autre appareil
            DispatchQueue.main.async { [weak self] in
                self?.downloadFromCloud()
            }

        case quotaViolationChange:
            print("[iCloud] Quota dépassé")

        case accountChange:
            print("[iCloud] Changement de compte iCloud")
            DispatchQueue.main.async { [weak self] in
                self?.downloadFromCloud()
            }

        default:
            break
        }
    }
}

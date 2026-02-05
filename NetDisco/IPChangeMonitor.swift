// IPChangeMonitor.swift
// NetDisco
//
// Service de détection de changement d'IP publique.
// Vérifie périodiquement l'IP via ipify.org et envoie une notification si elle change.

import Foundation

class IPChangeMonitor {

    static let shared = IPChangeMonitor()

    // UserDefaults keys
    private let enabledKey = "IPChangeDetectionEnabled"
    private let intervalKey = "IPChangeInterval"  // minutes
    private let lastIPKey = "LastKnownPublicIP"
    private let lastIPv6Key = "LastKnownPublicIPv6"
    private let lastCheckKey = "LastIPCheckDate"

    // Timer
    private var timer: Timer?
    private var isRunning = false

    // Callback pour notification (sera connecté à AppDelegate)
    var onIPChanged: ((String, String) -> Void)?  // (oldIP, newIP)
    var onIPv6Changed: ((String, String) -> Void)?

    // État actuel
    private(set) var currentIP: String?
    private(set) var currentIPv6: String?

    // MARK: - Configuration

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if newValue {
                start()
            } else {
                stop()
            }
        }
    }

    var intervalMinutes: Int {
        get {
            let val = UserDefaults.standard.integer(forKey: intervalKey)
            return val > 0 ? val : 5  // Défaut 5 minutes
        }
        set {
            UserDefaults.standard.set(max(1, newValue), forKey: intervalKey)
            if isRunning {
                restart()
            }
        }
    }

    var lastKnownIP: String? {
        get { UserDefaults.standard.string(forKey: lastIPKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastIPKey) }
    }

    var lastKnownIPv6: String? {
        get { UserDefaults.standard.string(forKey: lastIPv6Key) }
        set { UserDefaults.standard.set(newValue, forKey: lastIPv6Key) }
    }

    var lastCheckDate: Date? {
        get { UserDefaults.standard.object(forKey: lastCheckKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastCheckKey) }
    }

    // MARK: - Lifecycle

    func start() {
        guard isEnabled else { return }
        guard !isRunning else { return }

        isRunning = true
        let interval = TimeInterval(intervalMinutes * 60)

        // Vérifier immédiatement
        checkIP()

        // Puis périodiquement
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkIP()
        }

        // S'assurer que le timer fonctionne même en mode background
        RunLoop.current.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    func restart() {
        stop()
        start()
    }

    // MARK: - IP Check

    func checkIP() {
        checkIPv4()
        checkIPv6()
        lastCheckDate = Date()
    }

    private func checkIPv4() {
        guard let url = URL(string: "https://api.ipify.org") else { return }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            guard error == nil,
                  let data = data,
                  let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  self.isValidIPv4(ip) else {
                return
            }

            DispatchQueue.main.async {
                self.processIPv4(ip)
            }
        }.resume()
    }

    private func checkIPv6() {
        guard let url = URL(string: "https://api6.ipify.org") else { return }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            guard error == nil,
                  let data = data,
                  let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  self.isValidIPv6(ip) else {
                return
            }

            DispatchQueue.main.async {
                self.processIPv6(ip)
            }
        }.resume()
    }

    private func processIPv4(_ newIP: String) {
        let oldIP = lastKnownIP
        currentIP = newIP

        // Première fois - juste enregistrer
        guard let old = oldIP else {
            lastKnownIP = newIP
            return
        }

        // Changement détecté
        if old != newIP {
            lastKnownIP = newIP
            onIPChanged?(old, newIP)
            logIPChange(type: "IPv4", oldIP: old, newIP: newIP)
        }
    }

    private func processIPv6(_ newIP: String) {
        let oldIP = lastKnownIPv6
        currentIPv6 = newIP

        // Première fois - juste enregistrer
        guard let old = oldIP else {
            lastKnownIPv6 = newIP
            return
        }

        // Changement détecté
        if old != newIP {
            lastKnownIPv6 = newIP
            onIPv6Changed?(old, newIP)
            logIPChange(type: "IPv6", oldIP: old, newIP: newIP)
        }
    }

    // MARK: - Validation

    private func isValidIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let num = Int(part) else { return false }
            return num >= 0 && num <= 255
        }
    }

    private func isValidIPv6(_ ip: String) -> Bool {
        // Validation simple : contient ":" et pas de caractères invalides
        guard ip.contains(":") else { return false }
        let validChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF:")
        return ip.unicodeScalars.allSatisfy { validChars.contains($0) }
    }

    // MARK: - History

    private let historyKey = "IPChangeHistory"
    private let maxHistoryEntries = 50

    struct IPChangeEvent: Codable {
        let date: Date
        let type: String  // "IPv4" or "IPv6"
        let oldIP: String
        let newIP: String
    }

    private func logIPChange(type: String, oldIP: String, newIP: String) {
        var history = loadHistory()
        let event = IPChangeEvent(date: Date(), type: type, oldIP: oldIP, newIP: newIP)
        history.insert(event, at: 0)

        if history.count > maxHistoryEntries {
            history = Array(history.prefix(maxHistoryEntries))
        }

        saveHistory(history)
    }

    func loadHistory() -> [IPChangeEvent] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let history = try? JSONDecoder().decode([IPChangeEvent].self, from: data) else {
            return []
        }
        return history
    }

    private func saveHistory(_ history: [IPChangeEvent]) {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    func clearHistory() {
        UserDefaults.standard.removeObject(forKey: historyKey)
    }

    // MARK: - Force Check

    func forceCheck(completion: @escaping (String?, String?) -> Void) {
        let group = DispatchGroup()
        var ipv4Result: String?
        var ipv6Result: String?

        group.enter()
        if let url = URL(string: "https://api.ipify.org") {
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            URLSession.shared.dataTask(with: request) { data, _, _ in
                if let data = data, let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    ipv4Result = ip
                }
                group.leave()
            }.resume()
        } else {
            group.leave()
        }

        group.enter()
        if let url = URL(string: "https://api6.ipify.org") {
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            URLSession.shared.dataTask(with: request) { data, _, _ in
                if let data = data, let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    ipv6Result = ip
                }
                group.leave()
            }.resume()
        } else {
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            if let ip = ipv4Result {
                self?.processIPv4(ip)
            }
            if let ip = ipv6Result {
                self?.processIPv6(ip)
            }
            completion(ipv4Result, ipv6Result)
        }
    }
}

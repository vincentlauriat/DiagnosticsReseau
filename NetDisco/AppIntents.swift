// AppIntents.swift
// NetDisco — Raccourcis Siri via App Intents
// Permet d'utiliser Siri et l'app Raccourcis pour lancer des diagnostics réseau

import AppIntents
import AppKit
import Foundation

// MARK: - Lancer un test de débit

struct RunSpeedTestIntent: AppIntent {
    static var title: LocalizedStringResource = "Lancer un test de débit"
    static var description = IntentDescription("Lance un test de débit réseau avec NetDisco")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Ouvrir l'app et lancer le speed test via URL scheme
        if let url = URL(string: "netdisco://speedtest") {
            await MainActor.run {
                NSWorkspace.shared.open(url)
            }
        }
        return .result()
    }
}

// MARK: - Afficher les détails réseau

struct ShowNetworkDetailsIntent: AppIntent {
    static var title: LocalizedStringResource = "Afficher les détails réseau"
    static var description = IntentDescription("Affiche les informations détaillées du réseau")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        if let url = URL(string: "netdisco://details") {
            await MainActor.run {
                NSWorkspace.shared.open(url)
            }
        }
        return .result()
    }
}

// MARK: - Afficher la qualité réseau

struct ShowNetworkQualityIntent: AppIntent {
    static var title: LocalizedStringResource = "Afficher la qualité réseau"
    static var description = IntentDescription("Affiche les mesures de qualité réseau (latence, jitter, perte)")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        if let url = URL(string: "netdisco://quality") {
            await MainActor.run {
                NSWorkspace.shared.open(url)
            }
        }
        return .result()
    }
}

// MARK: - Lancer un traceroute

struct RunTracerouteIntent: AppIntent {
    static var title: LocalizedStringResource = "Lancer un traceroute"
    static var description = IntentDescription("Ouvre l'outil de traceroute pour analyser le chemin réseau")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Destination", description: "Adresse IP ou nom de domaine (optionnel)")
    var destination: String?

    func perform() async throws -> some IntentResult {
        var urlString = "netdisco://traceroute"
        if let dest = destination, !dest.isEmpty {
            urlString += "?target=\(dest.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? dest)"
        }
        if let url = URL(string: urlString) {
            await MainActor.run {
                NSWorkspace.shared.open(url)
            }
        }
        return .result()
    }
}

// MARK: - Afficher les infos WiFi

struct ShowWiFiInfoIntent: AppIntent {
    static var title: LocalizedStringResource = "Afficher les infos WiFi"
    static var description = IntentDescription("Affiche les détails de la connexion WiFi")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        if let url = URL(string: "netdisco://wifi") {
            await MainActor.run {
                NSWorkspace.shared.open(url)
            }
        }
        return .result()
    }
}

// MARK: - Lancer le diagnostic télétravail

struct RunTeletravailDiagnosticIntent: AppIntent {
    static var title: LocalizedStringResource = "Diagnostic télétravail"
    static var description = IntentDescription("Lance le diagnostic complet pour le télétravail")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        if let url = URL(string: "netdisco://teletravail") {
            await MainActor.run {
                NSWorkspace.shared.open(url)
            }
        }
        return .result()
    }
}

// MARK: - Requête DNS

struct RunDNSQueryIntent: AppIntent {
    static var title: LocalizedStringResource = "Requête DNS"
    static var description = IntentDescription("Ouvre l'outil de requête DNS")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Domaine", description: "Nom de domaine à interroger (optionnel)")
    var domain: String?

    func perform() async throws -> some IntentResult {
        var urlString = "netdisco://dns"
        if let dom = domain, !dom.isEmpty {
            urlString += "?query=\(dom.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? dom)"
        }
        if let url = URL(string: urlString) {
            await MainActor.run {
                NSWorkspace.shared.open(url)
            }
        }
        return .result()
    }
}

// MARK: - Requête WHOIS

struct RunWhoisQueryIntent: AppIntent {
    static var title: LocalizedStringResource = "Requête WHOIS"
    static var description = IntentDescription("Ouvre l'outil de requête WHOIS")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Domaine ou IP", description: "Domaine ou adresse IP à interroger (optionnel)")
    var target: String?

    func perform() async throws -> some IntentResult {
        var urlString = "netdisco://whois"
        if let t = target, !t.isEmpty {
            urlString += "?query=\(t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t)"
        }
        if let url = URL(string: urlString) {
            await MainActor.run {
                NSWorkspace.shared.open(url)
            }
        }
        return .result()
    }
}

// MARK: - App Shortcuts Provider

struct NetDiscoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunSpeedTestIntent(),
            phrases: [
                "Lance un test de débit avec \(.applicationName)",
                "Test de débit \(.applicationName)",
                "Teste ma connexion avec \(.applicationName)",
                "Vitesse internet \(.applicationName)"
            ],
            shortTitle: "Test de débit",
            systemImageName: "speedometer"
        )
        AppShortcut(
            intent: ShowNetworkDetailsIntent(),
            phrases: [
                "Affiche les détails réseau avec \(.applicationName)",
                "Infos réseau \(.applicationName)",
                "Mon réseau \(.applicationName)"
            ],
            shortTitle: "Détails réseau",
            systemImageName: "network"
        )
        AppShortcut(
            intent: ShowNetworkQualityIntent(),
            phrases: [
                "Qualité réseau avec \(.applicationName)",
                "Latence réseau \(.applicationName)",
                "Ping \(.applicationName)"
            ],
            shortTitle: "Qualité réseau",
            systemImageName: "waveform.path.ecg"
        )
        AppShortcut(
            intent: ShowWiFiInfoIntent(),
            phrases: [
                "Infos WiFi avec \(.applicationName)",
                "Signal WiFi \(.applicationName)",
                "Mon WiFi \(.applicationName)"
            ],
            shortTitle: "Infos WiFi",
            systemImageName: "wifi"
        )
        AppShortcut(
            intent: RunTeletravailDiagnosticIntent(),
            phrases: [
                "Diagnostic télétravail avec \(.applicationName)",
                "Test télétravail \(.applicationName)",
                "Vérifie ma connexion pour le télétravail \(.applicationName)"
            ],
            shortTitle: "Diagnostic télétravail",
            systemImageName: "house.and.flag"
        )
    }
}

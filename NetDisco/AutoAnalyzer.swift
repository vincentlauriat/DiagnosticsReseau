// AutoAnalyzer.swift
// NetDisco
//
// Moteur de diagnostic automatique. Analyse l'état du réseau et génère
// des alertes avec suggestions en français.

import Foundation

// MARK: - Network State

struct NetworkState {
    var isConnected: Bool = true
    var latencyMs: Double = 0
    var jitterMs: Double = 0
    var packetLossPercent: Double = 0
    var downloadMbps: Double? = nil
    var uploadMbps: Double? = nil
    var dnsResolutionMs: Double? = nil
    var rssiDbm: Int? = nil
    var isVPN: Bool = false
    var interfaceType: InterfaceType = .unknown

    enum InterfaceType {
        case wifi, ethernet, cellular, vpn, unknown
    }
}

// MARK: - Diagnostic Alert

enum AlertSeverity: Int, Comparable {
    case info = 0
    case warning = 1
    case critical = 2

    static func < (lhs: AlertSeverity, rhs: AlertSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var icon: String {
        switch self {
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .critical: return "🔴"
        }
    }

    var color: String {
        switch self {
        case .info: return "systemBlue"
        case .warning: return "systemOrange"
        case .critical: return "systemRed"
        }
    }
}

struct DiagnosticAlert: Identifiable {
    let id: String
    let severity: AlertSeverity
    let title: String
    let suggestion: String
    let timestamp: Date

    init(id: String, severity: AlertSeverity, titleKey: String, suggestionKey: String) {
        self.id = id
        self.severity = severity
        self.title = NSLocalizedString(titleKey, comment: "")
        self.suggestion = NSLocalizedString(suggestionKey, comment: "")
        self.timestamp = Date()
    }
}

// MARK: - Diagnostic Rules

struct DiagnosticRule {
    let id: String
    let titleKey: String
    let suggestionKey: String
    let severity: AlertSeverity
    let condition: (NetworkState) -> Bool
}

// MARK: - AutoAnalyzer

class AutoAnalyzer {

    static let shared = AutoAnalyzer()

    // Seuils configurables
    var highLatencyThreshold: Double = 100  // ms
    var criticalLatencyThreshold: Double = 300  // ms
    var highJitterThreshold: Double = 30  // ms
    var packetLossWarningThreshold: Double = 2  // %
    var packetLossCriticalThreshold: Double = 10  // %
    var slowDnsThreshold: Double = 200  // ms
    var weakSignalThreshold: Int = -70  // dBm
    var criticalSignalThreshold: Int = -80  // dBm
    var slowDownloadThreshold: Double = 5  // Mbps
    var slowUploadThreshold: Double = 1  // Mbps

    // Règles de diagnostic
    private lazy var rules: [DiagnosticRule] = [
        // Connexion
        DiagnosticRule(
            id: "no_connection",
            titleKey: "diagnostic.no_connection.title",
            suggestionKey: "diagnostic.no_connection.suggestion",
            severity: .critical,
            condition: { !$0.isConnected }
        ),

        // Latence
        DiagnosticRule(
            id: "critical_latency",
            titleKey: "diagnostic.critical_latency.title",
            suggestionKey: "diagnostic.critical_latency.suggestion",
            severity: .critical,
            condition: { [weak self] state in
                state.latencyMs > (self?.criticalLatencyThreshold ?? 300)
            }
        ),
        DiagnosticRule(
            id: "high_latency",
            titleKey: "diagnostic.high_latency.title",
            suggestionKey: "diagnostic.high_latency.suggestion",
            severity: .warning,
            condition: { [weak self] state in
                let threshold = self?.highLatencyThreshold ?? 100
                let critical = self?.criticalLatencyThreshold ?? 300
                return state.latencyMs > threshold && state.latencyMs <= critical
            }
        ),

        // Jitter
        DiagnosticRule(
            id: "high_jitter",
            titleKey: "diagnostic.high_jitter.title",
            suggestionKey: "diagnostic.high_jitter.suggestion",
            severity: .warning,
            condition: { [weak self] state in
                state.jitterMs > (self?.highJitterThreshold ?? 30)
            }
        ),

        // Perte de paquets
        DiagnosticRule(
            id: "critical_packet_loss",
            titleKey: "diagnostic.critical_packet_loss.title",
            suggestionKey: "diagnostic.critical_packet_loss.suggestion",
            severity: .critical,
            condition: { [weak self] state in
                state.packetLossPercent > (self?.packetLossCriticalThreshold ?? 10)
            }
        ),
        DiagnosticRule(
            id: "packet_loss",
            titleKey: "diagnostic.packet_loss.title",
            suggestionKey: "diagnostic.packet_loss.suggestion",
            severity: .warning,
            condition: { [weak self] state in
                let warning = self?.packetLossWarningThreshold ?? 2
                let critical = self?.packetLossCriticalThreshold ?? 10
                return state.packetLossPercent > warning && state.packetLossPercent <= critical
            }
        ),

        // DNS
        DiagnosticRule(
            id: "slow_dns",
            titleKey: "diagnostic.slow_dns.title",
            suggestionKey: "diagnostic.slow_dns.suggestion",
            severity: .warning,
            condition: { [weak self] state in
                guard let dns = state.dnsResolutionMs else { return false }
                return dns > (self?.slowDnsThreshold ?? 200)
            }
        ),

        // Signal WiFi
        DiagnosticRule(
            id: "critical_wifi_signal",
            titleKey: "diagnostic.critical_wifi_signal.title",
            suggestionKey: "diagnostic.critical_wifi_signal.suggestion",
            severity: .critical,
            condition: { [weak self] state in
                guard state.interfaceType == .wifi, let rssi = state.rssiDbm else { return false }
                return rssi < (self?.criticalSignalThreshold ?? -80)
            }
        ),
        DiagnosticRule(
            id: "weak_wifi_signal",
            titleKey: "diagnostic.weak_wifi_signal.title",
            suggestionKey: "diagnostic.weak_wifi_signal.suggestion",
            severity: .warning,
            condition: { [weak self] state in
                guard state.interfaceType == .wifi, let rssi = state.rssiDbm else { return false }
                let weak = self?.weakSignalThreshold ?? -70
                let critical = self?.criticalSignalThreshold ?? -80
                return rssi < weak && rssi >= critical
            }
        ),

        // Débit
        DiagnosticRule(
            id: "slow_download",
            titleKey: "diagnostic.slow_download.title",
            suggestionKey: "diagnostic.slow_download.suggestion",
            severity: .warning,
            condition: { [weak self] state in
                guard let download = state.downloadMbps else { return false }
                return download < (self?.slowDownloadThreshold ?? 5)
            }
        ),
        DiagnosticRule(
            id: "slow_upload",
            titleKey: "diagnostic.slow_upload.title",
            suggestionKey: "diagnostic.slow_upload.suggestion",
            severity: .info,
            condition: { [weak self] state in
                guard let upload = state.uploadMbps else { return false }
                return upload < (self?.slowUploadThreshold ?? 1)
            }
        ),

        // VPN
        DiagnosticRule(
            id: "vpn_latency",
            titleKey: "diagnostic.vpn_latency.title",
            suggestionKey: "diagnostic.vpn_latency.suggestion",
            severity: .info,
            condition: { state in
                state.isVPN && state.latencyMs > 50
            }
        ),
    ]

    // MARK: - Analysis

    func analyze(_ state: NetworkState) -> [DiagnosticAlert] {
        var alerts: [DiagnosticAlert] = []

        for rule in rules {
            if rule.condition(state) {
                let alert = DiagnosticAlert(
                    id: rule.id,
                    severity: rule.severity,
                    titleKey: rule.titleKey,
                    suggestionKey: rule.suggestionKey
                )
                alerts.append(alert)
            }
        }

        // Trier par sévérité (critique en premier)
        return alerts.sorted { $0.severity > $1.severity }
    }

    // MARK: - Quick Analysis (pour menu status)

    func quickAnalysis(_ state: NetworkState) -> (status: String, severity: AlertSeverity) {
        if !state.isConnected {
            return (NSLocalizedString("diagnostic.status.disconnected", comment: ""), .critical)
        }

        let alerts = analyze(state)

        if alerts.isEmpty {
            return (NSLocalizedString("diagnostic.status.good", comment: ""), .info)
        }

        let maxSeverity = alerts.map(\.severity).max() ?? .info
        let count = alerts.count
        let status: String

        switch maxSeverity {
        case .critical:
            status = String(format: NSLocalizedString("diagnostic.status.critical", comment: ""), count)
        case .warning:
            status = String(format: NSLocalizedString("diagnostic.status.warning", comment: ""), count)
        case .info:
            status = String(format: NSLocalizedString("diagnostic.status.info", comment: ""), count)
        }

        return (status, maxSeverity)
    }

    // MARK: - Generate Report

    func generateReport(_ state: NetworkState) -> String {
        var report = NSLocalizedString("diagnostic.report.title", comment: "") + "\n"
        report += String(repeating: "─", count: 40) + "\n\n"

        // État actuel
        report += NSLocalizedString("diagnostic.report.current_state", comment: "") + "\n"
        report += "• " + NSLocalizedString("diagnostic.report.connection", comment: "") + ": "
        report += state.isConnected ? "✓" : "✗"
        report += "\n"

        if state.latencyMs > 0 {
            report += "• " + NSLocalizedString("diagnostic.report.latency", comment: "") + ": "
            report += String(format: "%.1f ms\n", state.latencyMs)
        }

        if state.jitterMs > 0 {
            report += "• " + NSLocalizedString("diagnostic.report.jitter", comment: "") + ": "
            report += String(format: "%.1f ms\n", state.jitterMs)
        }

        if state.packetLossPercent > 0 {
            report += "• " + NSLocalizedString("diagnostic.report.packet_loss", comment: "") + ": "
            report += String(format: "%.1f%%\n", state.packetLossPercent)
        }

        if let rssi = state.rssiDbm {
            report += "• " + NSLocalizedString("diagnostic.report.wifi_signal", comment: "") + ": "
            report += "\(rssi) dBm\n"
        }

        report += "\n"

        // Alertes
        let alerts = analyze(state)
        if alerts.isEmpty {
            report += "✓ " + NSLocalizedString("diagnostic.report.no_issues", comment: "") + "\n"
        } else {
            report += NSLocalizedString("diagnostic.report.issues_found", comment: "") + "\n\n"
            for alert in alerts {
                report += "\(alert.severity.icon) \(alert.title)\n"
                report += "   → \(alert.suggestion)\n\n"
            }
        }

        return report
    }

    // MARK: - Utility

    func resetThresholdsToDefaults() {
        highLatencyThreshold = 100
        criticalLatencyThreshold = 300
        highJitterThreshold = 30
        packetLossWarningThreshold = 2
        packetLossCriticalThreshold = 10
        slowDnsThreshold = 200
        weakSignalThreshold = -70
        criticalSignalThreshold = -80
        slowDownloadThreshold = 5
        slowUploadThreshold = 1
    }
}

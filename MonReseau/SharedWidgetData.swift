// SharedWidgetData.swift
// Modeles partages entre l'app principale et le widget.
// Ce fichier doit etre ajoute aux deux targets (MonReseau + MonReseauWidget).

import Foundation

let appGroupID = "group.com.SmartColibri.MonReseau"
let widgetDataKey = "WidgetData"

struct WidgetData: Codable {
    let isConnected: Bool
    let latencyMs: Double?
    let vpnActive: Bool
    let wifiSSID: String?
    let wifiRSSI: Int?
    let uptimePercent: Double
    let disconnections24h: Int
    let lastSpeedTest: SpeedTestSummary?
    let recentSpeedTests: [SpeedTestSummary]
    let latencyHistory: [Double]
    let qualityRating: String?
    let updatedAt: Date
}

struct SpeedTestSummary: Codable {
    let date: Date
    let downloadMbps: Double
    let uploadMbps: Double
    let latencyMs: Double
    let location: String
}

func saveWidgetData(_ data: WidgetData) {
    guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
    if let encoded = try? JSONEncoder().encode(data) {
        defaults.set(encoded, forKey: widgetDataKey)
    }
}

func loadWidgetData() -> WidgetData? {
    guard let defaults = UserDefaults(suiteName: appGroupID),
          let data = defaults.data(forKey: widgetDataKey) else { return nil }
    return try? JSONDecoder().decode(WidgetData.self, from: data)
}

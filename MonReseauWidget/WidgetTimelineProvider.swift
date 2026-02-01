// WidgetTimelineProvider.swift
// Fournit les donnees au widget via App Group UserDefaults.

import WidgetKit
import SwiftUI

struct NetworkEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

struct NetworkTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NetworkEntry {
        NetworkEntry(date: Date(), data: Self.placeholderData)
    }

    func getSnapshot(in context: Context, completion: @escaping (NetworkEntry) -> Void) {
        let data = loadWidgetData() ?? Self.placeholderData
        completion(NetworkEntry(date: Date(), data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NetworkEntry>) -> Void) {
        let data = loadWidgetData() ?? Self.placeholderData
        let entry = NetworkEntry(date: Date(), data: data)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private static var placeholderData: WidgetData {
        WidgetData(
            isConnected: true,
            latencyMs: 12,
            vpnActive: false,
            wifiSSID: "WiFi",
            wifiRSSI: -45,
            uptimePercent: 99.8,
            disconnections24h: 0,
            lastSpeedTest: SpeedTestSummary(date: Date(), downloadMbps: 245, uploadMbps: 28, latencyMs: 12, location: "Paris, FR"),
            recentSpeedTests: [],
            latencyHistory: [12, 14, 11, 13, 15, 12, 10, 14, 13, 12],
            qualityRating: "Excellent",
            updatedAt: Date()
        )
    }
}

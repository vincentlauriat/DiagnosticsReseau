// LargeWidgetView.swift
// Widget grand : statut, WiFi, sparkline latence, 3 derniers speed tests, VPN.

import SwiftUI
import WidgetKit

struct LargeWidgetView: View {
    let data: WidgetData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header : statut + uptime
            HStack {
                Circle()
                    .fill(data.isConnected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(data.isConnected ? "Connecté" : "Déconnecté")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%.1f%%", data.uptimePercent))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // WiFi info
            if let ssid = data.wifiSSID {
                HStack(spacing: 4) {
                    Image(systemName: "wifi")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Text(ssid)
                        .font(.caption)
                    if let rssi = data.wifiRSSI {
                        Text("\(rssi) dBm")
                            .font(.caption2)
                            .foregroundColor(rssiColor(rssi))
                    }
                }
            }

            Divider()

            // Sparkline latence
            if !data.latencyHistory.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Latence")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    LatencySparkline(values: data.latencyHistory)
                        .frame(height: 40)
                }
            }

            Divider()

            // Derniers tests de debit
            VStack(alignment: .leading, spacing: 4) {
                Text("Derniers tests")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if data.recentSpeedTests.isEmpty {
                    Text("Aucun test")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(data.recentSpeedTests.indices, id: \.self) { i in
                        let test = data.recentSpeedTests[i]
                        HStack {
                            Text(test.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .frame(width: 100, alignment: .leading)
                            Spacer()
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(.blue)
                                Text(String(format: "%.0f", test.downloadMbps))
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                            }
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 8))
                                    .foregroundColor(.orange)
                                Text(String(format: "%.0f", test.uploadMbps))
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                            }
                            Text(String(format: "%.0f ms", test.latencyMs))
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(.green)
                        }
                    }
                }
            }

            // Bouton deep link speed test
            Link(destination: URL(string: "netdisco://speedtest")!) {
                Label("Lancer un test de débit", systemImage: "bolt.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
            }

            Spacer(minLength: 0)

            // Footer : VPN + localisation
            HStack {
                if let test = data.lastSpeedTest, !test.location.isEmpty {
                    Label(test.location, systemImage: "location.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if data.vpnActive {
                    Label("VPN", systemImage: "lock.shield.fill")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func rssiColor(_ rssi: Int) -> Color {
        if rssi > -50 { return .green }
        if rssi > -70 { return .orange }
        return .red
    }
}

// MARK: - Sparkline

struct LatencySparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxVal = values.max() ?? 1
            let minVal = values.min() ?? 0
            let range = max(maxVal - minVal, 1)

            Path { path in
                guard values.count > 1 else { return }
                let stepX = geo.size.width / CGFloat(values.count - 1)

                for (i, val) in values.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = geo.size.height - ((val - minVal) / range) * geo.size.height
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.green, lineWidth: 1.5)
        }
    }
}

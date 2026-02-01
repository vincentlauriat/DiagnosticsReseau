// SmallWidgetView.swift
// Widget petit : statut, latence, uptime.

import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let data: WidgetData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Statut connexion
            HStack(spacing: 6) {
                Circle()
                    .fill(data.isConnected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(data.isConnected ? "Connecté" : "Déconnecté")
                    .font(.caption)
                    .fontWeight(.medium)
            }

            Spacer()

            // Latence
            if let latency = data.latencyMs {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.0f ms", latency))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("latence")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else if let test = data.lastSpeedTest {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.0f ms", test.latencyMs))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("latence")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("—")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Uptime
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%.1f%%", data.uptimePercent))
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

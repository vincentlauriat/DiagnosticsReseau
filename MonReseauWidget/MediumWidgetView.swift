// MediumWidgetView.swift
// Widget moyen : statut, dernier speed test, VPN, localisation.

import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
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
                Text(String(format: "Uptime: %.1f%%", data.uptimePercent))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Speed test
            if let test = data.lastSpeedTest {
                HStack(spacing: 16) {
                    SpeedLabel(icon: "arrow.down", value: String(format: "%.0f", test.downloadMbps), unit: "Mbps", color: .blue)
                    SpeedLabel(icon: "arrow.up", value: String(format: "%.0f", test.uploadMbps), unit: "Mbps", color: .orange)
                    SpeedLabel(icon: "timer", value: String(format: "%.0f", test.latencyMs), unit: "ms", color: .green)
                }

                Text("Dernier test : \(test.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("Aucun test de débit")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            // Footer : localisation + VPN
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
        .widgetURL(URL(string: "monreseau://details"))
    }
}

struct SpeedLabel: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            Text(unit)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }
}

//
//  MonReseauWidget.swift
//  MonReseauWidget
//
//  Created by Vincent Lauriat on 01/02/2026.
//

import WidgetKit
import SwiftUI

struct NetworkStatusWidget: Widget {
    let kind: String = "NetworkStatus"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NetworkTimelineProvider()) { entry in
            NetworkWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Mon Réseau")
        .description("Statut réseau, latence et derniers tests de débit.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

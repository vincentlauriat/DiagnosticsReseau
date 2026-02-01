// NetworkWidgetEntryView.swift
// Vue principale qui dispatche vers Small/Medium/Large selon la famille.

import SwiftUI
import WidgetKit

struct NetworkWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: NetworkEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(data: entry.data)
        case .systemMedium:
            MediumWidgetView(data: entry.data)
        case .systemLarge:
            LargeWidgetView(data: entry.data)
        default:
            SmallWidgetView(data: entry.data)
        }
    }
}

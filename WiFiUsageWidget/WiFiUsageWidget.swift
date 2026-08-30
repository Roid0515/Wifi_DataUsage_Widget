import SwiftUI
import WidgetKit
import WiFiUsageCore

@main
struct WiFiUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WiFiUsageConstants.widgetKind, provider: WiFiUsageProvider()) { entry in
            WiFiUsageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Wi-Fi Usage")
        .description("Shows data used during the current Wi-Fi connection session.")
        .supportedFamilies([.systemSmall])
    }
}

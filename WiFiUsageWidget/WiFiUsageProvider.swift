import WidgetKit
import WiFiUsageCore

struct WiFiUsageEntry: TimelineEntry {
    let date: Date
    let snapshot: WiFiUsageSnapshot
    let showSSID: Bool
    let showTransferBreakdown: Bool
    let unitPreference: UnitPreference
}

struct WiFiUsageProvider: TimelineProvider {
    private let store = SharedSnapshotStore()

    func placeholder(in context: Context) -> WiFiUsageEntry {
        WiFiUsageEntry(
            date: Date(),
            snapshot: WiFiUsageSnapshot(
                isConnected: true,
                interfaceName: "en0",
                ssid: "Home Wi-Fi",
                sessionID: UUID(),
                sessionStartedAt: Date().addingTimeInterval(-7_800),
                lastUpdatedAt: Date(),
                rxBytes: 1_180_000_000,
                txBytes: 240_000_000
            ),
            showSSID: true,
            showTransferBreakdown: true,
            unitPreference: .automatic
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WiFiUsageEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WiFiUsageEntry>) -> Void) {
        let entry = entry()
        // WidgetCenter reload requests are budgeted by the system. A short fallback
        // timeline keeps the desktop value fresh even if a requested reload is deferred.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60))))
    }

    private func entry() -> WiFiUsageEntry {
        WiFiUsageEntry(
            date: Date(),
            snapshot: store.loadSnapshot(),
            showSSID: store.showSSID,
            showTransferBreakdown: store.showTransferBreakdown,
            unitPreference: store.unitPreference
        )
    }
}

import SwiftUI
import WiFiUsageCore

@main
struct WiFiUsageApp: App {
    @StateObject private var model = UsageMonitorModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model)
        } label: {
            Label(model.snapshot.isConnected ? "Wi-Fi Usage" : "Wi-Fi Disconnected",
                  systemImage: model.snapshot.isConnected ? "wifi" : "wifi.slash")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}

import AppKit
import SwiftUI
import WiFiUsageCore

struct MenuBarContentView: View {
    @ObservedObject var model: UsageMonitorModel
    @State private var showingResetConfirmation = false

    private var preference: UnitPreference { model.store.unitPreference }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: model.snapshot.isConnected ? "wifi" : "wifi.slash")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.snapshot.isConnected ? "Wi-Fi Connected" : "Wi-Fi Disconnected")
                        .font(.headline)
                    if let ssid = model.snapshot.ssid, model.store.showSSID {
                        Text(ssid).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            Text(UsageByteFormatter.string(from: model.snapshot.totalBytes, preference: preference))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()

            HStack(spacing: 18) {
                Label(UsageByteFormatter.string(from: model.snapshot.rxBytes, preference: preference),
                      systemImage: "arrow.down")
                Label(UsageByteFormatter.string(from: model.snapshot.txBytes, preference: preference),
                      systemImage: "arrow.up")
            }
            .font(.subheadline)

            if let duration = SessionDurationFormatter.string(from: model.snapshot.sessionStartedAt) {
                Label(duration, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Divider()
            HStack {
                Button("Reset Session") { showingResetConfirmation = true }
                SettingsLink { Text("Settings") }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 330)
        .alert("Reset current Wi-Fi session?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { model.resetCurrentSession() }
        } message: {
            Text("Usage will restart at 0 B without disconnecting the network.")
        }
    }
}

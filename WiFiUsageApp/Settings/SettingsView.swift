import SwiftUI
import WiFiUsageCore

struct SettingsView: View {
    @ObservedObject var model: UsageMonitorModel
    @State private var showSSID: Bool
    @State private var showTransferBreakdown: Bool
    @State private var unitPreference: UnitPreference
    @State private var showingResetConfirmation = false

    init(model: UsageMonitorModel) {
        self.model = model
        _showSSID = State(initialValue: model.store.showSSID)
        _showTransferBreakdown = State(initialValue: model.store.showTransferBreakdown)
        _unitPreference = State(initialValue: model.store.unitPreference)
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Toggle("Show SSID in Widget", isOn: $showSSID)
                    .onChange(of: showSSID) { _, value in
                        model.store.showSSID = value
                        model.reloadWidget()
                    }
                Toggle("Show RX/TX in Widget", isOn: $showTransferBreakdown)
                    .onChange(of: showTransferBreakdown) { _, value in
                        model.store.showTransferBreakdown = value
                        model.reloadWidget()
                    }
                Button("Reset Current Session", role: .destructive) {
                    showingResetConfirmation = true
                }
            }

            Section("Unit") {
                Picker("Display Unit", selection: $unitPreference) {
                    ForEach(UnitPreference.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .onChange(of: unitPreference) { _, value in
                    model.store.unitPreference = value
                    model.reloadWidget()
                }
            }

            if let error = model.lastError {
                Section("Status") { Text(error).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460, height: 360)
        .alert("Reset current Wi-Fi session?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { model.resetCurrentSession() }
        } message: {
            Text("Usage will restart at 0 B without disconnecting the network.")
        }
    }
}

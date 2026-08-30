import SwiftUI
import WidgetKit
import WiFiUsageCore

struct WiFiUsageWidgetView: View {
    let entry: WiFiUsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: entry.snapshot.isConnected ? "wifi" : "wifi.slash")
                Text("Wi-Fi Usage").fontWeight(.semibold)
            }
            .font(.caption)

            if entry.showSSID, entry.snapshot.isConnected {
                Text(entry.snapshot.ssid ?? "Connected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 3)
            }

            Spacer(minLength: 4)

            Text(UsageByteFormatter.string(
                from: entry.snapshot.totalBytes,
                preference: entry.unitPreference
            ))
            .font(.system(size: 27, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.65)
            .lineLimit(1)
            .monospacedDigit()
            .accessibilityLabel("Total usage")

            Spacer(minLength: 4)

            if entry.showTransferBreakdown {
                HStack(spacing: 7) {
                    transferLabel(systemName: "arrow.down", bytes: entry.snapshot.rxBytes)
                    transferLabel(systemName: "arrow.up", bytes: entry.snapshot.txBytes)
                }
            }

            HStack {
                if entry.snapshot.isConnected,
                   let duration = SessionDurationFormatter.string(from: entry.snapshot.sessionStartedAt, to: entry.date) {
                    Text(duration)
                } else {
                    Text("Disconnected")
                }
                Spacer()
                Text(entry.snapshot.lastUpdatedAt, style: .relative)
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.top, 5)
        }
    }

    private func transferLabel(systemName: String, bytes: UInt64) -> some View {
        Label(UsageByteFormatter.string(from: bytes, preference: entry.unitPreference), systemImage: systemName)
            .font(.system(size: 9, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

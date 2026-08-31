@preconcurrency import AppKit
import Combine
import Foundation
import ServiceManagement
import WidgetKit
import WiFiUsageCore

@MainActor
final class UsageMonitorModel: ObservableObject {
    @Published private(set) var snapshot: WiFiUsageSnapshot
    @Published var lastError: String?
    @Published private(set) var launchAtLoginEnabled: Bool

    private let connectionProvider: any WiFiConnectionProviding
    private let counterProvider: any NetworkCounterProviding
    private let bootTimeProvider: any SystemBootTimeProviding
    let store: SharedSnapshotStore
    private var engine: WiFiSessionEngine
    private var monitorTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var lastWidgetReload = Date.distantPast
    private var lastPersistedSnapshot: WiFiUsageSnapshot?

    init(
        connectionProvider: any WiFiConnectionProviding = CoreWLANConnectionProvider(),
        counterProvider: any NetworkCounterProviding = DarwinNetworkCounterProvider(),
        bootTimeProvider: any SystemBootTimeProviding = ProcessBootTimeProvider(),
        store: SharedSnapshotStore = SharedSnapshotStore()
    ) {
        self.connectionProvider = connectionProvider
        self.counterProvider = counterProvider
        self.bootTimeProvider = bootTimeProvider
        self.store = store
        snapshot = store.loadSnapshot()
        engine = WiFiSessionEngine(state: store.loadSessionState())
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.measure() }
        }

        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.measure()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    deinit {
        monitorTask?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    func measure() {
        let connection = connectionProvider.currentConnection()
        let counters: InterfaceCounters?

        if connection.isConnected, let name = connection.interfaceName {
            do {
                counters = try counterProvider.currentCounters(for: name)
                lastError = nil
            } catch {
                counters = nil
                lastError = error.localizedDescription
            }
        } else {
            counters = nil
            lastError = nil
        }

        // A transient statistics read failure must not destroy a valid session
        // baseline. Keep displaying the last good snapshot and try again shortly.
        if connection.isConnected && counters == nil {
            return
        }

        let next = engine.update(
            connection: connection,
            counters: counters,
            systemBootTime: bootTimeProvider.currentBootTime()
        )
        publish(next)
    }

    func resetCurrentSession() {
        let connection = connectionProvider.currentConnection()
        guard connection.isConnected,
              let name = connection.interfaceName,
              let counters = try? counterProvider.currentCounters(for: name) else {
            lastError = "A connected Wi-Fi interface is required to reset the session."
            return
        }
        let next = engine.reset(
            connection: connection,
            counters: counters,
            systemBootTime: bootTimeProvider.currentBootTime()
        )
        publish(next, forceWidgetReload: true)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            lastError = nil
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            lastError = error.localizedDescription
        }
    }

    func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: WiFiUsageConstants.widgetKind)
        lastWidgetReload = Date()
    }

    private func publish(_ next: WiFiUsageSnapshot, forceWidgetReload: Bool = false) {
        snapshot = next

        let now = Date()
        let previous = lastPersistedSnapshot
        let sessionChanged = next.isConnected
            && previous?.sessionID != next.sessionID
        let valueChanged = previous?.totalBytes != next.totalBytes
            || previous?.isConnected != next.isConnected
            || sessionChanged
        let shouldReloadWidget = WidgetReloadPolicy.shouldReload(
            previous: previous,
            next: next,
            secondsSinceLastReload: now.timeIntervalSince(lastWidgetReload)
        )

        if valueChanged || now.timeIntervalSince(previous?.lastUpdatedAt ?? .distantPast) >= 30 {
            store.save(snapshot: next, state: engine.state)
            lastPersistedSnapshot = next
        }

        if forceWidgetReload || shouldReloadWidget {
            reloadWidget()
        }
    }
}

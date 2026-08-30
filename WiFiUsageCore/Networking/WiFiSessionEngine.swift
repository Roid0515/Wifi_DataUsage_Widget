import Foundation

public struct WiFiSessionEngine: Sendable {
    public private(set) var state: WiFiSessionState?

    public init(state: WiFiSessionState? = nil) {
        self.state = state
    }

    @discardableResult
    public mutating func update(
        connection: WiFiConnection,
        counters: InterfaceCounters?,
        now: Date = Date(),
        systemBootTime: Date
    ) -> WiFiUsageSnapshot {
        guard connection.isConnected,
              let interfaceName = connection.interfaceName,
              let counters else {
            state = nil
            return .disconnected(at: now)
        }

        if shouldStartNewSession(
            connection: connection,
            counters: counters,
            systemBootTime: systemBootTime
        ) {
            state = makeState(
                connection: connection,
                interfaceName: interfaceName,
                counters: counters,
                now: now,
                systemBootTime: systemBootTime
            )
        } else {
            state?.lastRawRxBytes = counters.rxBytes
            state?.lastRawTxBytes = counters.txBytes
            if let ssid = connection.ssid {
                state?.ssid = ssid
            }
        }

        guard let state else { return .disconnected(at: now) }
        let rx = counters.rxBytes >= state.baselineRxBytes
            ? counters.rxBytes - state.baselineRxBytes
            : 0
        let tx = counters.txBytes >= state.baselineTxBytes
            ? counters.txBytes - state.baselineTxBytes
            : 0

        return WiFiUsageSnapshot(
            isConnected: true,
            interfaceName: state.interfaceName,
            ssid: connection.ssid ?? state.ssid,
            sessionID: state.sessionID,
            sessionStartedAt: state.sessionStartedAt,
            lastUpdatedAt: now,
            rxBytes: rx,
            txBytes: tx
        )
    }

    public mutating func reset(
        connection: WiFiConnection,
        counters: InterfaceCounters,
        now: Date = Date(),
        systemBootTime: Date
    ) -> WiFiUsageSnapshot {
        state = nil
        return update(
            connection: connection,
            counters: counters,
            now: now,
            systemBootTime: systemBootTime
        )
    }

    private func shouldStartNewSession(
        connection: WiFiConnection,
        counters: InterfaceCounters,
        systemBootTime: Date
    ) -> Bool {
        guard let state else { return true }
        if state.interfaceName != connection.interfaceName { return true }
        if let oldSSID = state.ssid, let newSSID = connection.ssid, oldSSID != newSSID {
            return true
        }
        if abs(state.systemBootTime.timeIntervalSince(systemBootTime)) > 30 { return true }
        if counters.rxBytes < state.baselineRxBytes || counters.txBytes < state.baselineTxBytes {
            return true
        }
        if counters.rxBytes < state.lastRawRxBytes || counters.txBytes < state.lastRawTxBytes {
            return true
        }
        return false
    }

    private func makeState(
        connection: WiFiConnection,
        interfaceName: String,
        counters: InterfaceCounters,
        now: Date,
        systemBootTime: Date
    ) -> WiFiSessionState {
        WiFiSessionState(
            sessionID: UUID(),
            interfaceName: interfaceName,
            ssid: connection.ssid,
            sessionStartedAt: now,
            baselineRxBytes: counters.rxBytes,
            baselineTxBytes: counters.txBytes,
            lastRawRxBytes: counters.rxBytes,
            lastRawTxBytes: counters.txBytes,
            systemBootTime: systemBootTime
        )
    }
}

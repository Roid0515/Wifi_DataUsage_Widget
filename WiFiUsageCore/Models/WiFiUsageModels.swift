import Foundation

public enum WiFiUsageConstants {
    public static let appGroupIdentifier = "ZA5PPDLD8T.local.wifiusage"
    public static let widgetKind = "WiFiUsageWidget"
}

public struct InterfaceCounters: Codable, Equatable, Sendable {
    public let rxBytes: UInt64
    public let txBytes: UInt64

    public init(rxBytes: UInt64, txBytes: UInt64) {
        self.rxBytes = rxBytes
        self.txBytes = txBytes
    }
}

public struct WiFiConnection: Equatable, Sendable {
    public let isConnected: Bool
    public let interfaceName: String?
    public let ssid: String?

    public init(isConnected: Bool, interfaceName: String?, ssid: String?) {
        self.isConnected = isConnected
        self.interfaceName = interfaceName
        self.ssid = ssid
    }

    public static let disconnected = WiFiConnection(
        isConnected: false,
        interfaceName: nil,
        ssid: nil
    )
}

public struct WiFiUsageSnapshot: Codable, Equatable, Sendable {
    public let isConnected: Bool
    public let interfaceName: String?
    public let ssid: String?
    public let sessionID: UUID
    public let sessionStartedAt: Date?
    public let lastUpdatedAt: Date
    public let rxBytes: UInt64
    public let txBytes: UInt64
    public let totalBytes: UInt64

    public init(
        isConnected: Bool,
        interfaceName: String?,
        ssid: String?,
        sessionID: UUID,
        sessionStartedAt: Date?,
        lastUpdatedAt: Date,
        rxBytes: UInt64,
        txBytes: UInt64
    ) {
        self.isConnected = isConnected
        self.interfaceName = interfaceName
        self.ssid = ssid
        self.sessionID = sessionID
        self.sessionStartedAt = sessionStartedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.rxBytes = rxBytes
        self.txBytes = txBytes
        self.totalBytes = rxBytes.addingReportingOverflow(txBytes).overflow
            ? UInt64.max
            : rxBytes + txBytes
    }

    public static func disconnected(at date: Date = Date()) -> WiFiUsageSnapshot {
        WiFiUsageSnapshot(
            isConnected: false,
            interfaceName: nil,
            ssid: nil,
            sessionID: UUID(),
            sessionStartedAt: nil,
            lastUpdatedAt: date,
            rxBytes: 0,
            txBytes: 0
        )
    }
}

public struct WiFiSessionState: Codable, Equatable, Sendable {
    public var sessionID: UUID
    public var interfaceName: String
    public var ssid: String?
    public var sessionStartedAt: Date
    public var baselineRxBytes: UInt64
    public var baselineTxBytes: UInt64
    public var lastRawRxBytes: UInt64
    public var lastRawTxBytes: UInt64
    public var systemBootTime: Date

    public init(
        sessionID: UUID,
        interfaceName: String,
        ssid: String?,
        sessionStartedAt: Date,
        baselineRxBytes: UInt64,
        baselineTxBytes: UInt64,
        lastRawRxBytes: UInt64,
        lastRawTxBytes: UInt64,
        systemBootTime: Date
    ) {
        self.sessionID = sessionID
        self.interfaceName = interfaceName
        self.ssid = ssid
        self.sessionStartedAt = sessionStartedAt
        self.baselineRxBytes = baselineRxBytes
        self.baselineTxBytes = baselineTxBytes
        self.lastRawRxBytes = lastRawRxBytes
        self.lastRawTxBytes = lastRawTxBytes
        self.systemBootTime = systemBootTime
    }
}

public enum WidgetReloadPolicy {
    public static func shouldReload(
        previous: WiFiUsageSnapshot?,
        next: WiFiUsageSnapshot,
        secondsSinceLastReload: TimeInterval,
        minimumUsageReloadInterval: TimeInterval = 60
    ) -> Bool {
        guard let previous else { return true }

        let connectionChanged = previous.isConnected != next.isConnected
        let sessionChanged = next.isConnected && previous.sessionID != next.sessionID
        if connectionChanged || sessionChanged {
            return true
        }

        let usageChanged = previous.totalBytes != next.totalBytes
        return usageChanged && secondsSinceLastReload >= minimumUsageReloadInterval
    }
}

public enum UnitPreference: String, CaseIterable, Identifiable, Sendable {
    case automatic = "Auto"
    case megabytes = "MB"
    case gigabytes = "GB"

    public var id: String { rawValue }
}

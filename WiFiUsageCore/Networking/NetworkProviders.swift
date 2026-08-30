import CoreWLAN
import Darwin
import Foundation

public enum NetworkCounterError: LocalizedError {
    case interfaceNotFound(String)
    case statisticsUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case let .interfaceNotFound(name):
            "Network interface \(name) was not found."
        case let .statisticsUnavailable(name):
            "Statistics for network interface \(name) are unavailable."
        }
    }
}

public protocol WiFiConnectionProviding: Sendable {
    func currentConnection() -> WiFiConnection
}

public protocol NetworkCounterProviding: Sendable {
    func currentCounters(for interfaceName: String) throws -> InterfaceCounters
}

public protocol SystemBootTimeProviding: Sendable {
    func currentBootTime() -> Date
}

public struct CoreWLANConnectionProvider: WiFiConnectionProviding {
    public init() {}

    public func currentConnection() -> WiFiConnection {
        guard let interface = CWWiFiClient.shared().interface(),
              let name = interface.interfaceName else {
            return .disconnected
        }

        // SSID/BSSID can be hidden by privacy policy. Radio metrics remain
        // available and let usage tracking continue without location access.
        let ssid = interface.ssid()
        let running = interface.powerOn()
            && (ssid != nil
                || interface.bssid() != nil
                || interface.transmitRate() > 0
                || interface.rssiValue() != 0)
        return WiFiConnection(
            isConnected: running,
            interfaceName: name,
            ssid: running ? ssid : nil
        )
    }
}

public struct DarwinNetworkCounterProvider: NetworkCounterProviding {
    public init() {}

    public func currentCounters(for interfaceName: String) throws -> InterfaceCounters {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let firstAddress = addresses else {
            throw NetworkCounterError.interfaceNotFound(interfaceName)
        }
        defer { freeifaddrs(addresses) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let address = cursor {
            let entry = address.pointee
            if String(cString: entry.ifa_name) == interfaceName,
               let socketAddress = entry.ifa_addr,
               socketAddress.pointee.sa_family == UInt8(AF_LINK) {
                guard let rawData = entry.ifa_data else {
                    throw NetworkCounterError.statisticsUnavailable(interfaceName)
                }
                let data = rawData.assumingMemoryBound(to: if_data.self).pointee
                return InterfaceCounters(
                    rxBytes: UInt64(data.ifi_ibytes),
                    txBytes: UInt64(data.ifi_obytes)
                )
            }
            cursor = entry.ifa_next
        }

        throw NetworkCounterError.interfaceNotFound(interfaceName)
    }
}

public struct ProcessBootTimeProvider: SystemBootTimeProviding {
    public init() {}

    public func currentBootTime() -> Date {
        var mib = [CTL_KERN, KERN_BOOTTIME]
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride
        let result = mib.withUnsafeMutableBufferPointer { pointer in
            sysctl(pointer.baseAddress, 2, &bootTime, &size, nil, 0)
        }
        guard result == 0 else {
            return Date(timeIntervalSinceNow: -ProcessInfo.processInfo.systemUptime)
        }
        return Date(
            timeIntervalSince1970: TimeInterval(bootTime.tv_sec)
                + TimeInterval(bootTime.tv_usec) / 1_000_000
        )
    }
}

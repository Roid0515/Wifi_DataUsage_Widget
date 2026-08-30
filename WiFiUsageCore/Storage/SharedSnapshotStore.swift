import Foundation

public final class SharedSnapshotStore: @unchecked Sendable {
    public enum Keys {
        public static let snapshot = "wifiUsage.snapshot"
        public static let sessionState = "wifiUsage.sessionState"
        public static let showSSID = "wifiUsage.showSSID"
        public static let showTransferBreakdown = "wifiUsage.showTransferBreakdown"
        public static let unitPreference = "wifiUsage.unitPreference"
    }

    private struct SnapshotFile: Codable {
        let snapshot: WiFiUsageSnapshot
        let sessionState: WiFiSessionState?
    }

    private struct SettingsFile: Codable {
        var showSSID = true
        var showTransferBreakdown = true
        var unitPreferenceRawValue = UnitPreference.automatic.rawValue
    }

    private enum Backend {
        case files(snapshotURL: URL, settingsURL: URL)
        case defaults(UserDefaults)
    }

    private let backend: Backend
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(appGroupIdentifier: String = WiFiUsageConstants.appGroupIdentifier) {
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            backend = .files(
                snapshotURL: containerURL.appendingPathComponent("WiFiUsageSnapshot.json"),
                settingsURL: containerURL.appendingPathComponent("WiFiUsageSettings.json")
            )
        } else {
            let defaults = UserDefaults.standard
            backend = .defaults(defaults)
            Self.registerDefaults(in: defaults)
        }
    }

    public init(defaults: UserDefaults) {
        backend = .defaults(defaults)
        Self.registerDefaults(in: defaults)
    }

    public func loadSnapshot() -> WiFiUsageSnapshot {
        switch backend {
        case let .files(snapshotURL, _):
            return load(SnapshotFile.self, from: snapshotURL)?.snapshot ?? .disconnected()
        case let .defaults(defaults):
            guard let data = defaults.data(forKey: Keys.snapshot),
                  let snapshot = try? decoder.decode(WiFiUsageSnapshot.self, from: data) else {
                return .disconnected()
            }
            return snapshot
        }
    }

    public func save(snapshot: WiFiUsageSnapshot, state: WiFiSessionState?) {
        switch backend {
        case let .files(snapshotURL, _):
            save(SnapshotFile(snapshot: snapshot, sessionState: state), to: snapshotURL)
        case let .defaults(defaults):
            if let snapshotData = try? encoder.encode(snapshot) {
                defaults.set(snapshotData, forKey: Keys.snapshot)
            }
            if let state, let stateData = try? encoder.encode(state) {
                defaults.set(stateData, forKey: Keys.sessionState)
            } else {
                defaults.removeObject(forKey: Keys.sessionState)
            }
        }
    }

    public func loadSessionState() -> WiFiSessionState? {
        switch backend {
        case let .files(snapshotURL, _):
            return load(SnapshotFile.self, from: snapshotURL)?.sessionState
        case let .defaults(defaults):
            guard let data = defaults.data(forKey: Keys.sessionState) else { return nil }
            return try? decoder.decode(WiFiSessionState.self, from: data)
        }
    }

    public var showSSID: Bool {
        get {
            switch backend {
            case let .files(_, settingsURL): return loadSettings(from: settingsURL).showSSID
            case let .defaults(defaults): return defaults.bool(forKey: Keys.showSSID)
            }
        }
        set {
            switch backend {
            case let .files(_, settingsURL):
                var settings = loadSettings(from: settingsURL)
                settings.showSSID = newValue
                save(settings, to: settingsURL)
            case let .defaults(defaults): defaults.set(newValue, forKey: Keys.showSSID)
            }
        }
    }

    public var showTransferBreakdown: Bool {
        get {
            switch backend {
            case let .files(_, settingsURL): return loadSettings(from: settingsURL).showTransferBreakdown
            case let .defaults(defaults): return defaults.bool(forKey: Keys.showTransferBreakdown)
            }
        }
        set {
            switch backend {
            case let .files(_, settingsURL):
                var settings = loadSettings(from: settingsURL)
                settings.showTransferBreakdown = newValue
                save(settings, to: settingsURL)
            case let .defaults(defaults): defaults.set(newValue, forKey: Keys.showTransferBreakdown)
            }
        }
    }

    public var unitPreference: UnitPreference {
        get {
            switch backend {
            case let .files(_, settingsURL):
                return UnitPreference(rawValue: loadSettings(from: settingsURL).unitPreferenceRawValue) ?? .automatic
            case let .defaults(defaults):
                return UnitPreference(rawValue: defaults.string(forKey: Keys.unitPreference) ?? "") ?? .automatic
            }
        }
        set {
            switch backend {
            case let .files(_, settingsURL):
                var settings = loadSettings(from: settingsURL)
                settings.unitPreferenceRawValue = newValue.rawValue
                save(settings, to: settingsURL)
            case let .defaults(defaults): defaults.set(newValue.rawValue, forKey: Keys.unitPreference)
            }
        }
    }

    private func loadSettings(from url: URL) -> SettingsFile {
        load(SettingsFile.self, from: url) ?? SettingsFile()
    }

    private func load<Value: Decodable>(_ type: Value.Type, from url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func save<Value: Encodable>(_ value: Value, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func registerDefaults(in defaults: UserDefaults) {
        defaults.register(defaults: [
            Keys.showSSID: true,
            Keys.showTransferBreakdown: true,
            Keys.unitPreference: UnitPreference.automatic.rawValue
        ])
    }
}

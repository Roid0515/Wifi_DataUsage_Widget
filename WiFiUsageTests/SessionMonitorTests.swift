import Foundation
import XCTest
@testable import WiFiUsageCore

final class SessionMonitorTests: XCTestCase {
    private let bootTime = Date(timeIntervalSince1970: 1_000)
    private let startTime = Date(timeIntervalSince1970: 10_000)

    func testNormalAccumulation() {
        var engine = WiFiSessionEngine()
        let connection = WiFiConnection(isConnected: true, interfaceName: "en0", ssid: "WiFi_A")

        _ = engine.update(
            connection: connection,
            counters: InterfaceCounters(rxBytes: 100, txBytes: 50),
            now: startTime,
            systemBootTime: bootTime
        )
        let snapshot = engine.update(
            connection: connection,
            counters: InterfaceCounters(rxBytes: 300, txBytes: 100),
            now: startTime.addingTimeInterval(5),
            systemBootTime: bootTime
        )

        XCTAssertEqual(snapshot.rxBytes, 200)
        XCTAssertEqual(snapshot.txBytes, 50)
        XCTAssertEqual(snapshot.totalBytes, 250)
    }

    func testCounterDecreaseStartsNewSessionWithoutNegativeUsage() {
        var engine = WiFiSessionEngine()
        let connection = WiFiConnection(isConnected: true, interfaceName: "en0", ssid: "WiFi_A")
        let first = engine.update(
            connection: connection,
            counters: InterfaceCounters(rxBytes: 1_000, txBytes: 500),
            now: startTime,
            systemBootTime: bootTime
        )
        let reset = engine.update(
            connection: connection,
            counters: InterfaceCounters(rxBytes: 100, txBytes: 20),
            now: startTime.addingTimeInterval(5),
            systemBootTime: bootTime
        )

        XCTAssertNotEqual(first.sessionID, reset.sessionID)
        XCTAssertEqual(reset.totalBytes, 0)
    }

    func testSSIDChangeStartsNewSession() {
        var engine = WiFiSessionEngine()
        let first = engine.update(
            connection: WiFiConnection(isConnected: true, interfaceName: "en0", ssid: "WiFi_A"),
            counters: InterfaceCounters(rxBytes: 100, txBytes: 50),
            now: startTime,
            systemBootTime: bootTime
        )
        let second = engine.update(
            connection: WiFiConnection(isConnected: true, interfaceName: "en0", ssid: "WiFi_B"),
            counters: InterfaceCounters(rxBytes: 150, txBytes: 70),
            now: startTime.addingTimeInterval(5),
            systemBootTime: bootTime
        )

        XCTAssertNotEqual(first.sessionID, second.sessionID)
        XCTAssertEqual(second.totalBytes, 0)
    }

    func testDisconnectThenReconnectStartsNewSession() {
        var engine = WiFiSessionEngine()
        let connection = WiFiConnection(isConnected: true, interfaceName: "en0", ssid: "WiFi_A")
        let first = engine.update(
            connection: connection,
            counters: InterfaceCounters(rxBytes: 100, txBytes: 50),
            now: startTime,
            systemBootTime: bootTime
        )
        let disconnected = engine.update(
            connection: .disconnected,
            counters: nil,
            now: startTime.addingTimeInterval(5),
            systemBootTime: bootTime
        )
        let reconnected = engine.update(
            connection: connection,
            counters: InterfaceCounters(rxBytes: 200, txBytes: 100),
            now: startTime.addingTimeInterval(10),
            systemBootTime: bootTime
        )

        XCTAssertFalse(disconnected.isConnected)
        XCTAssertNotEqual(first.sessionID, reconnected.sessionID)
        XCTAssertEqual(reconnected.totalBytes, 0)
    }

    func testRestoredSessionContinuesAfterRelaunch() throws {
        let suiteName = "WiFiUsageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SharedSnapshotStore(defaults: defaults)
        let connection = WiFiConnection(isConnected: true, interfaceName: "en0", ssid: "WiFi_A")
        var initialEngine = WiFiSessionEngine()
        let initial = initialEngine.update(
            connection: connection,
            counters: InterfaceCounters(rxBytes: 100, txBytes: 50),
            now: startTime,
            systemBootTime: bootTime
        )
        store.save(snapshot: initial, state: initialEngine.state)

        var restoredEngine = WiFiSessionEngine(state: store.loadSessionState())
        let restored = restoredEngine.update(
            connection: connection,
            counters: InterfaceCounters(rxBytes: 300, txBytes: 100),
            now: startTime.addingTimeInterval(5),
            systemBootTime: bootTime
        )

        XCTAssertEqual(initial.sessionID, restored.sessionID)
        XCTAssertEqual(restored.rxBytes, 200)
        XCTAssertEqual(restored.txBytes, 50)
    }

    func testRebootStartsNewSession() {
        var engine = WiFiSessionEngine()
        let connection = WiFiConnection(isConnected: true, interfaceName: "en0", ssid: nil)
        let first = engine.update(
            connection: connection,
            counters: InterfaceCounters(rxBytes: 100, txBytes: 50),
            now: startTime,
            systemBootTime: bootTime
        )
        let afterReboot = engine.update(
            connection: connection,
            counters: InterfaceCounters(rxBytes: 110, txBytes: 60),
            now: startTime.addingTimeInterval(5),
            systemBootTime: bootTime.addingTimeInterval(120)
        )

        XCTAssertNotEqual(first.sessionID, afterReboot.sessionID)
        XCTAssertEqual(afterReboot.totalBytes, 0)
    }
}

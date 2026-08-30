import XCTest
@testable import WiFiUsageCore

final class ByteFormatterTests: XCTestCase {
    func testAutomaticUnitBoundaries() {
        XCTAssertEqual(UsageByteFormatter.string(from: 999), "999 B")
        XCTAssertEqual(UsageByteFormatter.string(from: 1_000), "1 KB")
        XCTAssertEqual(UsageByteFormatter.string(from: 999_000), "999 KB")
        XCTAssertEqual(UsageByteFormatter.string(from: 1_000_000), "1 MB")
        XCTAssertEqual(UsageByteFormatter.string(from: 999_000_000), "999 MB")
        XCTAssertEqual(UsageByteFormatter.string(from: 1_000_000_000), "1 GB")
        XCTAssertEqual(UsageByteFormatter.string(from: 1_420_000_000), "1.42 GB")
    }

    func testForcedUnits() {
        XCTAssertEqual(UsageByteFormatter.string(from: 1_500_000, preference: .megabytes), "1.5 MB")
        XCTAssertEqual(UsageByteFormatter.string(from: 1_500_000_000, preference: .gigabytes), "1.5 GB")
    }

    func testTotalOverflowSaturates() {
        let snapshot = WiFiUsageSnapshot(
            isConnected: true,
            interfaceName: "en0",
            ssid: nil,
            sessionID: UUID(),
            sessionStartedAt: Date(),
            lastUpdatedAt: Date(),
            rxBytes: UInt64.max,
            txBytes: 1
        )
        XCTAssertEqual(snapshot.totalBytes, UInt64.max)
    }
}

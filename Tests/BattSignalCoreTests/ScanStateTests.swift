import XCTest
@testable import BattSignalCore

final class ScanStateTests: XCTestCase {
    private let earlier = Date(timeIntervalSince1970: 1_000)
    private let now = Date(timeIntervalSince1970: 2_000)

    private var afterSuccess: ScanState { .finished(nil, lastSucceededAt: earlier) }

    func testStartingKeepsLastSuccess() {
        XCTAssertEqual(ScanState.idle.applying(.started), .scanning(lastSucceededAt: nil))
        XCTAssertEqual(afterSuccess.applying(.started), .scanning(lastSucceededAt: earlier))
        XCTAssertTrue(afterSuccess.applying(.started).isScanning)
        XCTAssertFalse(afterSuccess.isScanning)
    }

    func testMissingToolIsAProblemAndKeepsLastSuccess() {
        XCTAssertEqual(afterSuccess.applying(.toolMissing), .finished(.toolMissing, lastSucceededAt: earlier))
    }

    func testEmptyScanClearsProblemWithoutCountingAsSuccess() {
        let state = ScanState.scanning(lastSucceededAt: earlier)
            .applying(.listed(deviceCount: 0, failures: [], at: now))

        XCTAssertEqual(state, .finished(nil, lastSucceededAt: earlier))
    }

    func testScanReadingEveryDeviceIsASuccess() {
        let state = ScanState.scanning(lastSucceededAt: earlier)
            .applying(.listed(deviceCount: 1, failures: [], at: now))

        XCTAssertEqual(state, .finished(nil, lastSucceededAt: now))
    }

    func testAnyUnreadableDeviceIsAProblemAndNotASuccess() {
        let state = ScanState.scanning(lastSucceededAt: earlier)
            .applying(.listed(deviceCount: 2, failures: ["Momo"], at: now))

        XCTAssertEqual(state, .finished(.unreadable(["Momo"]), lastSucceededAt: earlier))
    }

    func testListFailureIsAProblemAndKeepsLastSuccess() {
        let state = ScanState.scanning(lastSucceededAt: earlier).applying(.listFailed("timed out"))

        XCTAssertEqual(state, .finished(.listFailed("timed out"), lastSucceededAt: earlier))
    }

    func testProblemMessages() {
        XCTAssertEqual(ScanProblem.toolMissing.message, "pymobiledevice3 isn't installed, so iPhones and iPads can't be read.")
        XCTAssertEqual(ScanProblem.unreadable(["Momo", "iPad"]).message, "Couldn't read Momo, iPad. It may be asleep or off this Wi-Fi.")
        XCTAssertEqual(ScanProblem.listFailed("timed out").message, "Scan failed: timed out")
    }
}

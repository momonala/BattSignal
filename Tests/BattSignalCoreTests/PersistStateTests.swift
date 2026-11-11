import XCTest
@testable import BattSignalCore

final class PersistStateTests: XCTestCase {
    private func snapshot(
        at seconds: TimeInterval,
        level: Int = 50,
        charging: Bool = false,
        externalPower: Bool = false
    ) -> Snapshot {
        Snapshot(
            device: DeviceInfo(id: "00008110-0000000000000001", name: "Momo", kind: .iphone),
            observer: Observer(id: "mac-air", name: "mac-air"),
            observedAt: Date(timeIntervalSince1970: seconds),
            battery: BatteryReading(level: level, isCharging: charging, externalPower: externalPower)
        )
    }

    private func written(_ snapshot: Snapshot) -> PersistState {
        var state = PersistState()
        state.didWrite(snapshot)
        return state
    }

    private func appended(_ snapshot: Snapshot) -> PersistState {
        var state = PersistState()
        state.didAppendHistory(snapshot)
        return state
    }

    func testFirstObservationIsWritten() {
        XCTAssertTrue(PersistState().needsWrite(snapshot(at: 0)))
    }

    func testUnwrittenObservationIsRetried() {
        var state = PersistState()
        state.didAppendHistory(snapshot(at: 0))

        XCTAssertTrue(state.needsWrite(snapshot(at: 1)))
    }

    func testLevelChangeIsWrittenImmediately() {
        XCTAssertTrue(written(snapshot(at: 0, level: 50)).needsWrite(snapshot(at: 1, level: 49)))
    }

    func testChargingChangeIsWrittenImmediately() {
        XCTAssertTrue(written(snapshot(at: 0, charging: false)).needsWrite(snapshot(at: 1, charging: true)))
    }

    func testExternalPowerChangeIsWrittenImmediately() {
        XCTAssertTrue(written(snapshot(at: 0, externalPower: false)).needsWrite(snapshot(at: 1, externalPower: true)))
    }

    func testUnchangedReadingIsRewrittenOnlyOnceTenMinutesOld() {
        let state = written(snapshot(at: 0))

        XCTAssertFalse(state.needsWrite(snapshot(at: 599)))
        XCTAssertTrue(state.needsWrite(snapshot(at: 600)))
        XCTAssertTrue(state.needsWrite(snapshot(at: 601)))
    }

    func testFirstHistoryPointIsAppended() {
        XCTAssertTrue(PersistState().needsHistory(snapshot(at: 0)))
    }

    func testHistoryIsAppendedEveryFourteenAndAHalfMinutes() {
        let state = appended(snapshot(at: 0))

        XCTAssertFalse(state.needsHistory(snapshot(at: 869)))
        XCTAssertTrue(state.needsHistory(snapshot(at: 870)))
        XCTAssertTrue(state.needsHistory(snapshot(at: 871)))
    }

    func testWriteAndHistoryThrottlesAreIndependent() {
        let state = written(snapshot(at: 0))

        XCTAssertTrue(state.needsHistory(snapshot(at: 1)))
    }
}

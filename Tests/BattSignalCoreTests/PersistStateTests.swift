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

    private struct SaveFailed: Error {}

    private func written(_ snapshots: Snapshot...) -> PersistState {
        var state = PersistState()
        for snapshot in snapshots { try! state.writeIfNeeded(snapshot) { _ in } }
        return state
    }

    private func appended(_ snapshots: Snapshot...) -> PersistState {
        var state = PersistState()
        for snapshot in snapshots { try! state.appendHistoryIfNeeded(snapshot) { _ in } }
        return state
    }

    func testFirstObservationIsWritten() {
        XCTAssertTrue(PersistState().needsWrite(snapshot(at: 0)))
    }

    func testHistoryAloneDoesNotCountAsWritten() {
        XCTAssertTrue(appended(snapshot(at: 0)).needsWrite(snapshot(at: 1)))
    }

    func testSuccessfulWriteIsRecordedAndReported() throws {
        var state = PersistState()
        var saved: [Snapshot] = []

        XCTAssertTrue(try state.writeIfNeeded(snapshot(at: 0)) { saved.append($0) })
        XCTAssertFalse(try state.writeIfNeeded(snapshot(at: 1)) { saved.append($0) })
        XCTAssertEqual(saved, [snapshot(at: 0)])
    }

    func testFailedWriteThrowsAndIsRetriedNextTime() throws {
        var state = PersistState()

        XCTAssertThrowsError(try state.writeIfNeeded(snapshot(at: 0)) { _ in throw SaveFailed() })
        XCTAssertTrue(try state.writeIfNeeded(snapshot(at: 1)) { _ in })
    }

    func testFailedHistoryAppendThrowsAndIsRetriedNextTime() throws {
        var state = PersistState()
        var appendedAt: [Date] = []

        XCTAssertThrowsError(try state.appendHistoryIfNeeded(snapshot(at: 0)) { _ in throw SaveFailed() })
        try state.appendHistoryIfNeeded(snapshot(at: 1)) { appendedAt.append($0.observedAt) }
        XCTAssertEqual(appendedAt, [Date(timeIntervalSince1970: 1)])
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

    func testRewriteRestartsTheWriteClock() {
        XCTAssertFalse(written(snapshot(at: 0), snapshot(at: 600)).needsWrite(snapshot(at: 601)))
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

    func testAppendRestartsTheHistoryClock() {
        XCTAssertFalse(appended(snapshot(at: 0), snapshot(at: 870)).needsHistory(snapshot(at: 871)))
    }

    func testWriteAndHistoryThrottlesAreIndependent() {
        let state = written(snapshot(at: 0))

        XCTAssertTrue(state.needsHistory(snapshot(at: 1)))
    }
}

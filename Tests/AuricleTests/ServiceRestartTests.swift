import XCTest
@testable import Auricle

/// coreaudiod restart: dead chains are forgotten first, rebuilt once afterwards, and never
/// rebuilt on top of a chain that an apply/updateSource already built in between.
final class ServiceRestartStateTests: XCTestCase {
    func testLiveChainIsDiscardedThenRebuiltOnce() {
        var state = ServiceRestartState()
        XCTAssertTrue(state.discard(hasChain: true))
        XCTAssertTrue(state.shouldRebuild(hasChain: false))
        XCTAssertFalse(state.shouldRebuild(hasChain: false), "a second rebuild request must be a no-op")
    }

    func testNoRebuildWhenChainWasAlreadyRebuiltInBetween() {
        // updateSource/apply queued by the refreshes built a fresh chain after the discard:
        // rebuilding again would drop it (the original leak).
        var state = ServiceRestartState()
        XCTAssertTrue(state.discard(hasChain: true))
        XCTAssertFalse(state.shouldRebuild(hasChain: true))
        XCTAssertFalse(state.rebuildPending)
    }

    func testEngineWithoutChainIsNotRebuilt() {
        var state = ServiceRestartState()
        XCTAssertFalse(state.discard(hasChain: false))
        XCTAssertFalse(state.shouldRebuild(hasChain: false))
    }

    func testRebuildWithoutPriorDiscardIsNoOp() {
        var state = ServiceRestartState()
        XCTAssertFalse(state.shouldRebuild(hasChain: false))
    }
}

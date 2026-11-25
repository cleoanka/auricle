import CoreAudio
import XCTest
@testable import Auricle

/// A recorded engine failure must not pin an app at 100% forever: it is retried once the
/// app shows up with a different process-object set than the one that failed.
final class EngineErrorRetryTests: XCTestCase {
    private let error = ["com.zoom": "the tapped process quit"]

    func testRelaunchedAppWithNewObjectIDsIsRetried() {
        let keys = AudioController.retriableErrorKeys(errors: error,
                                                      failedObjectIDs: ["com.zoom": [41, 42]],
                                                      currentObjectIDs: ["com.zoom": [77]])
        XCTAssertEqual(keys, ["com.zoom"])
    }

    func testSameObjectIDsStayGated() {
        // No build/fail loop: an unchanged process set keeps its error.
        let keys = AudioController.retriableErrorKeys(errors: error,
                                                      failedObjectIDs: ["com.zoom": [41, 42]],
                                                      currentObjectIDs: ["com.zoom": [41, 42]])
        XCTAssertEqual(keys, [])
    }

    func testAbsentAppStaysGated() {
        let keys = AudioController.retriableErrorKeys(errors: error,
                                                      failedObjectIDs: ["com.zoom": [41]],
                                                      currentObjectIDs: ["com.other": [41]])
        XCTAssertEqual(keys, [])
    }

    func testErrorWithoutRecordedObjectIDsIsRetriedWhenAppIsPresent() {
        let keys = AudioController.retriableErrorKeys(errors: error,
                                                      failedObjectIDs: [:],
                                                      currentObjectIDs: ["com.zoom": [41]])
        XCTAssertEqual(keys, ["com.zoom"])
    }

    func testMasterKeyIsNeverRetriedByProcessChanges() {
        let keys = AudioController.retriableErrorKeys(errors: ["__auricle.master__": "no usable output device"],
                                                      failedObjectIDs: [:],
                                                      currentObjectIDs: ["com.zoom": [41]])
        XCTAssertEqual(keys, [])
    }
}

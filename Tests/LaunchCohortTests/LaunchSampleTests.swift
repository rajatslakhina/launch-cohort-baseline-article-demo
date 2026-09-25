import XCTest
@testable import LaunchCohort

final class LaunchSampleTests: XCTestCase {
    func testValidSampleConstructs() {
        guard let sample = LaunchSample(osVersion: "27.0", processStart: 0, preMainEnd: 0.3, firstFrame: 0.5) else {
            XCTFail("expected a valid sample")
            return
        }
        XCTAssertEqual(sample.coldLaunchDuration, 0.5, accuracy: 1e-9)
        XCTAssertEqual(sample.preMainDuration, 0.3, accuracy: 1e-9)
        XCTAssertEqual(sample.postMainDuration, 0.2, accuracy: 1e-9)
    }

    func testOutOfOrderTimestampsFailInit() {
        // firstFrame before preMainEnd is physically impossible; must fail, not produce a negative duration.
        XCTAssertNil(LaunchSample(osVersion: "27.0", processStart: 0, preMainEnd: 0.5, firstFrame: 0.3))
        // preMainEnd before processStart, same reasoning.
        XCTAssertNil(LaunchSample(osVersion: "27.0", processStart: 0.5, preMainEnd: 0.1, firstFrame: 0.6))
    }

    func testEmptyOSVersionFailsInit() {
        XCTAssertNil(LaunchSample(osVersion: "", processStart: 0, preMainEnd: 0.1, firstFrame: 0.2))
    }

    func testMajorVersionCohortParsing() {
        let sample = LaunchSample(osVersion: "27.1", processStart: 0, preMainEnd: 0.1, firstFrame: 0.2)
        XCTAssertEqual(sample?.majorVersionCohort, "27")
    }

    func testMajorVersionCohortFallsBackWhenNoDot() {
        // Not the expected "major.minor" shape — falls back to the raw string rather than crashing.
        let sample = LaunchSample(osVersion: "beta3", processStart: 0, preMainEnd: 0.1, firstFrame: 0.2)
        XCTAssertEqual(sample?.majorVersionCohort, "beta3")
    }
}

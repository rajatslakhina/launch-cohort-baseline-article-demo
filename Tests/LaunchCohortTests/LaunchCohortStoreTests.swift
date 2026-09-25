import XCTest
@testable import LaunchCohort

final class LaunchCohortStoreTests: XCTestCase {
    private func sample(_ os: String, cold: TimeInterval) -> LaunchSample {
        // preMain fixed at 40% of cold duration, postMain the remainder — arbitrary but internally consistent.
        LaunchSample(osVersion: os, processStart: 0, preMainEnd: cold * 0.4, firstFrame: cold)!
    }

    func testBlendedPercentileOnEmptyStoreReturnsNil() {
        let store = LaunchCohortStore()
        XCTAssertNil(store.blendedPercentile(0.5, of: \.coldLaunchDuration))
    }

    func testBlendedPercentileKnownDataset() {
        let store = LaunchCohortStore()
        // 1...10 seconds, nearest-rank p50 of a 10-element sorted array (index 4 or 5) and p100.
        for i in 1...10 {
            store.record(sample("27.0", cold: TimeInterval(i)))
        }
        let p50 = store.blendedPercentile(0.5, of: \.coldLaunchDuration)
        guard let pMax = store.blendedPercentile(1.0, of: \.coldLaunchDuration),
              let pMin = store.blendedPercentile(0.0, of: \.coldLaunchDuration) else {
            XCTFail("expected percentiles on a non-empty store")
            return
        }
        XCTAssertNotNil(p50)
        XCTAssertEqual(pMax, 10, accuracy: 1e-9)
        XCTAssertEqual(pMin, 1, accuracy: 1e-9)
    }

    func testCohortPercentileBelowMinimumSampleSizeReturnsNil() {
        let store = LaunchCohortStore()
        // One below the minimum (4 < minimumCohortSampleSize of 5).
        for i in 1...(minimumCohortSampleSize - 1) {
            store.record(sample("27.0", cold: TimeInterval(i)))
        }
        XCTAssertEqual(store.sampleCount(forCohort: "27"), minimumCohortSampleSize - 1)
        XCTAssertNil(store.cohortPercentile(0.5, cohort: "27", of: \.coldLaunchDuration))
    }

    func testCohortPercentileAtMinimumSampleSizeSucceeds() {
        let store = LaunchCohortStore()
        for i in 1...minimumCohortSampleSize {
            store.record(sample("27.0", cold: TimeInterval(i)))
        }
        XCTAssertNotNil(store.cohortPercentile(0.5, cohort: "27", of: \.coldLaunchDuration))
    }

    func testCohortPercentileForUnknownCohortReturnsNil() {
        let store = LaunchCohortStore()
        for i in 1...minimumCohortSampleSize {
            store.record(sample("27.0", cold: TimeInterval(i)))
        }
        XCTAssertNil(store.cohortPercentile(0.5, cohort: "99", of: \.coldLaunchDuration))
    }

    func testCohortsListsDistinctMajorVersionsSorted() {
        let store = LaunchCohortStore()
        store.record(sample("27.1", cold: 1))
        store.record(sample("26.4", cold: 1))
        store.record(sample("27.0", cold: 1))
        XCTAssertEqual(store.cohorts, ["26", "27"])
    }

    func testPercentileClampsOutOfRangeInputWithoutCrashing() {
        // p outside [0, 1] must clamp rather than index out of bounds.
        let values: [TimeInterval] = [1, 2, 3]
        XCTAssertEqual(LaunchCohortStore.percentile(-5, of: values), 1)
        XCTAssertEqual(LaunchCohortStore.percentile(5, of: values), 3)
    }

    func testPercentileOnSingleElementArray() {
        XCTAssertEqual(LaunchCohortStore.percentile(0.5, of: [4.2]), 4.2)
    }
}

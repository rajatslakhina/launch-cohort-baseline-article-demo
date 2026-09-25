import XCTest
@testable import LaunchCohort

final class LaunchTelemetrySummaryTests: XCTestCase {
    private func sample(_ os: String, cold: TimeInterval) -> LaunchSample {
        LaunchSample(osVersion: os, processStart: 0, preMainEnd: cold * 0.4, firstFrame: cold)!
    }

    func testReturnsNilWhenBaselineHasNoSamples() {
        let baseline = LaunchCohortStore()
        let current = LaunchCohortStore()
        for i in 1...minimumCohortSampleSize {
            current.record(sample("27.0", cold: TimeInterval(i)))
        }
        XCTAssertNil(LaunchTelemetrySummary.compare(baseline: baseline, current: current))
    }

    func testDetectsMaskedRegressionAcrossAPlatformMigration() {
        // Baseline window (last week): most of the fleet is still on iOS 26.
        // A minority has already migrated to 27, and — thanks to the
        // platform's pre-main win — that minority's cold launch is already
        // a bit faster than 26's, even before this week's code shipped.
        let baseline = LaunchCohortStore()
        for _ in 0..<20 {
            baseline.record(sample("26.4", cold: 1.00))
        }
        for _ in 0..<5 {
            baseline.record(sample("27.0", cold: 0.85))
        }

        // Current window (this week): the fleet finished migrating — 27 is
        // now the majority — and a post-main regression shipped that hits
        // 27 specifically (26 is untouched, same 1.00s as before).
        let current = LaunchCohortStore()
        for _ in 0..<5 {
            current.record(sample("26.4", cold: 1.00))
        }
        for _ in 0..<25 {
            current.record(sample("27.0", cold: 1.05))
        }

        guard let summary = LaunchTelemetrySummary.compare(baseline: baseline, current: current, threshold: 0.08) else {
            XCTFail("expected a summary")
            return
        }

        // Blended p50 (1.00 -> 1.05) reads as a mild ~5% regression. But cohort 27's own
        // trend (0.85 -> 1.05) is a ~23.5% regression — the migration mix is diluting the
        // number that would otherwise have paged someone.
        XCTAssertEqual(summary.blendedDeltaFraction, 0.05, accuracy: 1e-9)
        let cohort27 = summary.cohortTrends.first { $0.cohort == "27" }
        XCTAssertNotNil(cohort27)
        XCTAssertEqual(cohort27?.deltaFraction ?? 0, (1.05 - 0.85) / 0.85, accuracy: 1e-9)
        XCTAssertTrue(summary.hasMaskedRegression, "expected the 27 cohort's regression to be flagged")
        XCTAssertTrue(summary.maskedFindings.contains { $0.cohort == "27" })
        // The unaffected 26 cohort must not be flagged.
        XCTAssertFalse(summary.maskedFindings.contains { $0.cohort == "26" })
    }

    func testNoMaskedRegressionWhenCohortsMoveTogether() {
        let baseline = LaunchCohortStore()
        let current = LaunchCohortStore()
        for _ in 0..<20 {
            baseline.record(sample("27.0", cold: 1.0))
            current.record(sample("27.0", cold: 1.0))
        }
        guard let summary = LaunchTelemetrySummary.compare(baseline: baseline, current: current, threshold: 0.05) else {
            XCTFail("expected a summary")
            return
        }
        XCTAssertFalse(summary.hasMaskedRegression)
    }

    func testCohortOnlyInCurrentWindowIsExcludedFromTrends() {
        // A cohort with zero presence in the baseline can't have a trend — it should be
        // skipped rather than treated as an infinite/undefined regression.
        let baseline = LaunchCohortStore()
        for _ in 0..<20 {
            baseline.record(sample("26.4", cold: 1.0))
        }
        let current = LaunchCohortStore()
        for _ in 0..<20 {
            current.record(sample("26.4", cold: 1.0))
        }
        for _ in 0..<20 {
            current.record(sample("27.0", cold: 0.8)) // brand-new cohort, no baseline to compare against
        }
        guard let summary = LaunchTelemetrySummary.compare(baseline: baseline, current: current) else {
            XCTFail("expected a summary")
            return
        }
        XCTAssertFalse(summary.cohortTrends.contains { $0.cohort == "27" })
    }
}

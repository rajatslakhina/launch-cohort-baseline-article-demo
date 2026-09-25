import XCTest
@testable import LaunchCohort

final class RegressionMaskingTests: XCTestCase {
    func testFlatBlendCanMaskARealCohortRegression() {
        // The canonical scenario: iOS 27's pre-main win makes the *blended*
        // number look flat (0% change) while iOS 27's own post-main code
        // regressed by 15%.
        let trends = [
            CohortTrend(cohort: "27", baselineP50: 1.0, currentP50: 1.15)
        ]
        let findings = RegressionMasking.detect(trends: trends, blendedDeltaFraction: 0.0, threshold: 0.10)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.cohort, "27")
        XCTAssertEqual(findings.first?.divergence ?? 0, 0.15, accuracy: 1e-9)
    }

    func testDivergenceBelowThresholdIsNotFlagged() {
        let trends = [
            CohortTrend(cohort: "27", baselineP50: 1.0, currentP50: 1.05)
        ]
        let findings = RegressionMasking.detect(trends: trends, blendedDeltaFraction: 0.0, threshold: 0.10)
        XCTAssertTrue(findings.isEmpty)
    }

    func testDivergenceJustAboveThresholdIsFlagged() {
        // A comfortable margin above the threshold (0.10 vs 0.30), rather than an exact
        // floating-point boundary, to check the strict-greater-than comparison without
        // coupling the test to double-precision rounding at the boundary itself.
        let trends = [
            CohortTrend(cohort: "27", baselineP50: 1.0, currentP50: 1.30)
        ]
        let findings = RegressionMasking.detect(trends: trends, blendedDeltaFraction: 0.0, threshold: 0.10)
        XCTAssertEqual(findings.count, 1)
    }

    func testNegativeThresholdIsClampedToZero() {
        // A caller passing a negative threshold should not be able to force every cohort to fire.
        let trends = [
            CohortTrend(cohort: "27", baselineP50: 1.0, currentP50: 1.0) // zero divergence
        ]
        let findings = RegressionMasking.detect(trends: trends, blendedDeltaFraction: 0.0, threshold: -1.0)
        XCTAssertTrue(findings.isEmpty)
    }

    func testEmptyTrendsProducesEmptyFindings() {
        let findings = RegressionMasking.detect(trends: [], blendedDeltaFraction: 0.0, threshold: 0.10)
        XCTAssertTrue(findings.isEmpty)
    }

    func testFindingsSortedWorstFirst() {
        let trends = [
            CohortTrend(cohort: "26", baselineP50: 1.0, currentP50: 1.12),
            CohortTrend(cohort: "27", baselineP50: 1.0, currentP50: 1.40)
        ]
        let findings = RegressionMasking.detect(trends: trends, blendedDeltaFraction: 0.0, threshold: 0.10)
        XCTAssertEqual(findings.map(\.cohort), ["27", "26"])
    }

    func testDeltaFractionGuardsZeroBaseline() {
        // A zero baseline would divide-by-zero; deltaFraction must return a safe 0 instead of NaN/inf.
        let trend = CohortTrend(cohort: "27", baselineP50: 0, currentP50: 1.0)
        XCTAssertEqual(trend.deltaFraction, 0)
    }
}

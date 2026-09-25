import Foundation

/// Ties `LaunchCohortStore` and `RegressionMasking` together into the one
/// call a dashboard or a nightly job actually wants: "compare launch time
/// now against a prior baseline, per cohort, and tell me which cohorts the
/// blended number is lying about."
public enum LaunchTelemetrySummary {
    /// - Parameters:
    ///   - baseline: samples from the prior window (e.g. last week).
    ///   - current: samples from the window you're evaluating.
    ///   - threshold: divergence threshold passed through to
    ///     `RegressionMasking.detect`.
    /// - Returns: `nil` when there isn't enough data in *either* window to
    ///   say anything (blended p50 unavailable for one side) — a summary
    ///   with a confident zero is worse than admitting there isn't one yet.
    public static func compare(
        baseline: LaunchCohortStore,
        current: LaunchCohortStore,
        threshold: Double = 0.10
    ) -> Summary? {
        guard
            let blendedBaseline = baseline.blendedPercentile(0.5, of: \.coldLaunchDuration),
            let blendedCurrent = current.blendedPercentile(0.5, of: \.coldLaunchDuration),
            blendedBaseline > 0
        else { return nil }

        let blendedDeltaFraction = (blendedCurrent - blendedBaseline) / blendedBaseline

        // Only cohorts present (with enough samples) in *both* windows can
        // produce a trend — comparing a cohort against itself where it
        // didn't exist yet is not a trend, it's a category error.
        let cohortsToCheck = Set(baseline.cohorts).intersection(current.cohorts)

        var trends: [CohortTrend] = []
        for cohort in cohortsToCheck.sorted() {
            guard
                let basePercentile = baseline.cohortPercentile(0.5, cohort: cohort, of: \.coldLaunchDuration),
                let currentPercentile = current.cohortPercentile(0.5, cohort: cohort, of: \.coldLaunchDuration)
            else { continue }
            trends.append(CohortTrend(cohort: cohort, baselineP50: basePercentile, currentP50: currentPercentile))
        }

        let findings = RegressionMasking.detect(
            trends: trends,
            blendedDeltaFraction: blendedDeltaFraction,
            threshold: threshold
        )

        return Summary(
            blendedBaselineP50: blendedBaseline,
            blendedCurrentP50: blendedCurrent,
            blendedDeltaFraction: blendedDeltaFraction,
            cohortTrends: trends,
            maskedFindings: findings
        )
    }

    public struct Summary: Sendable, Equatable {
        public let blendedBaselineP50: TimeInterval
        public let blendedCurrentP50: TimeInterval
        public let blendedDeltaFraction: Double
        public let cohortTrends: [CohortTrend]
        public let maskedFindings: [MaskedRegressionFinding]

        public var hasMaskedRegression: Bool { !maskedFindings.isEmpty }
    }
}

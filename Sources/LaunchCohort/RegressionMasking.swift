import Foundation

/// One cohort's launch-time trend at a point in time, relative to a prior
/// baseline for that same cohort.
public struct CohortTrend: Sendable, Equatable {
    public let cohort: String
    public let baselineP50: TimeInterval
    public let currentP50: TimeInterval

    /// Positive means slower (a regression); negative means faster.
    public var deltaSeconds: TimeInterval { currentP50 - baselineP50 }

    public var deltaFraction: Double {
        guard baselineP50 > 0 else { return 0 }
        return deltaSeconds / baselineP50
    }
}

/// A cohort whose own trend disagrees with the blended, all-cohorts trend
/// by more than `threshold` — meaning the blended number is actively
/// hiding what's happening to that cohort's users.
public struct MaskedRegressionFinding: Sendable, Equatable {
    public let cohort: String
    public let cohortDeltaFraction: Double
    public let blendedDeltaFraction: Double

    /// How far the cohort's trend diverges from the blended trend, in the
    /// same fractional units as both deltas. Always >= the threshold that
    /// produced this finding.
    public var divergence: Double { cohortDeltaFraction - blendedDeltaFraction }
}

/// Compares each cohort's launch-time trend against the blended trend and
/// flags the cohorts where the blend is masking a real regression.
///
/// The canonical case this exists for: iOS 27 made pre-main ~20-30% faster
/// fleet-wide. If you ship a genuine regression in your own post-main code
/// during the same window, your *blended* p50 can stay flat or even
/// improve — the platform win absorbs it — while the growing iOS 27
/// cohort's post-main number is quietly getting worse underneath that
/// blend. `detect` is the check that catches that.
public enum RegressionMasking {
    /// - Parameters:
    ///   - trends: per-cohort trend, one entry per cohort you want checked.
    ///   - blendedDeltaFraction: the fractional change in the blended
    ///     (unsegmented) p50 over the same window, e.g. from
    ///     `LaunchCohortStore.blendedPercentile`.
    ///   - threshold: minimum divergence (as a fraction, e.g. 0.10 for 10%)
    ///     between a cohort's trend and the blended trend before it's
    ///     reported. Clamped to be >= 0 so a negative threshold can't be
    ///     used to force spurious findings.
    /// - Returns: findings for cohorts whose divergence from the blended
    ///   trend exceeds `threshold`, sorted worst-first. Empty when nothing
    ///   diverges, never when `trends` is empty either.
    public static func detect(
        trends: [CohortTrend],
        blendedDeltaFraction: Double,
        threshold: Double = 0.10
    ) -> [MaskedRegressionFinding] {
        let safeThreshold = max(threshold, 0)
        let findings = trends.compactMap { trend -> MaskedRegressionFinding? in
            let divergence = trend.deltaFraction - blendedDeltaFraction
            guard divergence > safeThreshold else { return nil }
            return MaskedRegressionFinding(
                cohort: trend.cohort,
                cohortDeltaFraction: trend.deltaFraction,
                blendedDeltaFraction: blendedDeltaFraction
            )
        }
        return findings.sorted { $0.divergence > $1.divergence }
    }
}

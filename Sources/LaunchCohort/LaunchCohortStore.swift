import Foundation

/// The minimum number of samples a cohort needs before `LaunchCohortStore`
/// will report a percentile for it. Below this, a percentile is noise
/// wearing a number's clothes, and pretending otherwise is how a lead ends
/// up defending a launch-time regression using a sample size of three.
public let minimumCohortSampleSize = 5

/// Collects launch samples and produces two kinds of readouts on request:
/// a **blended** percentile across every sample regardless of OS version
/// (what most launch dashboards show by default), and a **per-cohort**
/// percentile scoped to one OS major version (what you actually need
/// during a platform migration).
///
/// This type is intentionally synchronous and in-memory: it's the shape a
/// batch job or a unit test reasons about, not a production ingestion
/// pipeline. Swap the storage for whatever your telemetry backend uses;
/// the percentile and masking math is the part worth keeping.
public final class LaunchCohortStore {
    private var samples: [LaunchSample] = []

    public init() {}

    public init(samples: [LaunchSample]) {
        self.samples = samples
    }

    public func record(_ sample: LaunchSample) {
        samples.append(sample)
    }

    public func record(contentsOf newSamples: [LaunchSample]) {
        samples.append(contentsOf: newSamples)
    }

    public var sampleCount: Int { samples.count }

    /// All distinct major-version cohorts currently present, sorted for
    /// stable iteration (numeric where possible, lexical otherwise).
    public var cohorts: [String] {
        let unique = Set(samples.map(\.majorVersionCohort))
        return unique.sorted { lhs, rhs in
            if let l = Int(lhs), let r = Int(rhs) { return l < r }
            return lhs < rhs
        }
    }

    /// The blended percentile of `duration` across *every* recorded sample,
    /// independent of OS version. `p` is clamped to `[0, 1]`. Returns `nil`
    /// when there are no samples at all — never a crash, never a fabricated
    /// zero.
    public func blendedPercentile(_ p: Double, of duration: (LaunchSample) -> TimeInterval) -> TimeInterval? {
        Self.percentile(p, of: samples.map(duration))
    }

    /// The percentile of `duration` scoped to one major-version cohort
    /// (e.g. "27"). Returns `nil` when the cohort doesn't exist or has
    /// fewer than `minimumCohortSampleSize` samples — the guard against
    /// reading a trend out of statistical noise.
    public func cohortPercentile(_ p: Double, cohort: String, of duration: (LaunchSample) -> TimeInterval) -> TimeInterval? {
        let scoped = samples.filter { $0.majorVersionCohort == cohort }
        guard scoped.count >= minimumCohortSampleSize else { return nil }
        return Self.percentile(p, of: scoped.map(duration))
    }

    /// How many samples belong to a given cohort. Never negative, never
    /// out of bounds — a plain count over a filter.
    public func sampleCount(forCohort cohort: String) -> Int {
        samples.filter { $0.majorVersionCohort == cohort }.count
    }

    /// Nearest-rank percentile over a value array. Bounds-checked: `p` is
    /// clamped into `[0, 1]` before use, and the computed index is clamped
    /// into the array's valid range, so this never force-unwraps and never
    /// indexes out of bounds — including for a single-element or empty
    /// input.
    static func percentile(_ p: Double, of values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let clampedP = min(max(p, 0), 1)
        let sorted = values.sorted()
        let rawIndex = clampedP * Double(sorted.count - 1)
        let index = min(max(Int(rawIndex.rounded()), 0), sorted.count - 1)
        return sorted[index]
    }
}

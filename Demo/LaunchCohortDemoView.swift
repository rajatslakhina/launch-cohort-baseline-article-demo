import SwiftUI
import LaunchCohort

/// Synthetic fleet data standing in for two weeks of real launch telemetry:
/// last week (mostly iOS 26, a little iOS 27 already migrated) versus this
/// week (iOS 27 now the majority, and a post-main regression shipped that
/// only hits the 27 cohort). This is the exact shape the article argues
/// every launch dashboard should be able to show and currently can't.
enum DemoFleet {
    static func baseline() -> LaunchCohortStore {
        let store = LaunchCohortStore()
        for i in 0..<48 {
            let jitter = Double(i % 5) * 0.004
            store.record(makeSample(os: "26.4", cold: 1.02 + jitter))
        }
        for i in 0..<12 {
            let jitter = Double(i % 5) * 0.004
            store.record(makeSample(os: "27.0", cold: 0.83 + jitter))
        }
        return store
    }

    static func current() -> LaunchCohortStore {
        let store = LaunchCohortStore()
        for i in 0..<10 {
            let jitter = Double(i % 5) * 0.004
            store.record(makeSample(os: "26.4", cold: 1.02 + jitter))
        }
        for i in 0..<52 {
            let jitter = Double(i % 5) * 0.004
            // Pre-main still fast, but a shipped regression in post-main
            // (the code this app's own team owns) pushes cold launch up.
            store.record(makeSample(os: "27.0", cold: 1.01 + jitter))
        }
        return store
    }

    private static func makeSample(os: String, cold: TimeInterval) -> LaunchSample {
        let preMain = cold * 0.35
        // Force-unwrap avoided: this constructor input is always internally
        // consistent (preMain <= cold by construction), but we still fall
        // back to a same-instant sample instead of crashing if that were
        // ever violated by a future edit here.
        LaunchSample(osVersion: os, processStart: 0, preMainEnd: preMain, firstFrame: cold)
            ?? LaunchSample(osVersion: os, processStart: 0, preMainEnd: 0, firstFrame: 0)!
    }
}

struct LaunchCohortDemoView: View {
    private let summary: LaunchTelemetrySummary.Summary?

    init() {
        summary = LaunchTelemetrySummary.compare(
            baseline: DemoFleet.baseline(),
            current: DemoFleet.current(),
            threshold: 0.08
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let summary {
                        blendedCard(summary)
                        cohortSection(summary)
                        findingsSection(summary)
                    } else {
                        Text("Not enough data in one of the two windows.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Launch Cohort Baseline")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Blended vs. cohort launch trend")
                .font(.title2.bold())
            Text("Same two telemetry windows, read two ways. One of them is lying to you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func blendedCard(_ summary: LaunchTelemetrySummary.Summary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Blended fleet p50", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
            HStack {
                metric("Baseline", summary.blendedBaselineP50)
                metric("Current", summary.blendedCurrentP50)
                deltaBadge(summary.blendedDeltaFraction)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func cohortSection(_ summary: LaunchTelemetrySummary.Summary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Per-cohort trend", systemImage: "square.stack.3d.up")
                .font(.headline)
            ForEach(summary.cohortTrends, id: \.cohort) { trend in
                let isMasked = summary.maskedFindings.contains { $0.cohort == trend.cohort }
                HStack {
                    Text("iOS \(trend.cohort)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    metric("Baseline", trend.baselineP50)
                    metric("Current", trend.currentP50)
                    deltaBadge(trend.deltaFraction)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isMasked ? Color.red.opacity(0.12) : Color.gray.opacity(0.08))
                )
            }
        }
    }

    private func findingsSection(_ summary: LaunchTelemetrySummary.Summary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                summary.hasMaskedRegression ? "Masked regression found" : "No masked regression",
                systemImage: summary.hasMaskedRegression ? "exclamationmark.triangle.fill" : "checkmark.seal.fill"
            )
            .font(.headline)
            .foregroundStyle(summary.hasMaskedRegression ? .red : .green)

            ForEach(summary.maskedFindings, id: \.cohort) { finding in
                Text("iOS \(finding.cohort): cohort moved \(percentString(finding.cohortDeltaFraction)) while the blended fleet metric moved only \(percentString(finding.blendedDeltaFraction)).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func metric(_ label: String, _ value: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(String(format: "%.0f ms", value * 1000)).font(.subheadline.monospacedDigit())
        }
    }

    private func deltaBadge(_ fraction: Double) -> some View {
        let regressed = fraction > 0
        return Text(percentString(fraction))
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(regressed ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
            .foregroundStyle(regressed ? .red : .green)
            .clipShape(Capsule())
    }

    private func percentString(_ fraction: Double) -> String {
        String(format: "%+.1f%%", fraction * 100)
    }
}

#Preview {
    LaunchCohortDemoView()
}

import Foundation

/// One measured app launch, tagged with the OS version it ran on.
///
/// `LaunchCohort` exists because a single global p50/p95 over launch time is
/// only correct when every device in the fleet is running the same OS. The
/// moment a platform release changes launch performance underneath you —
/// which iOS 27 did, by roughly 20-30% in pre-main — that global number
/// becomes a blend of two populations migrating at a rate nobody controls.
/// `LaunchSample` is the atomic unit that lets you split the blend back
/// apart by `osVersion` before you read another number.
public struct LaunchSample: Sendable, Equatable {
    /// The OS version string this launch ran under, e.g. "26.1" or "27.0".
    /// Kept as a string (not a semantic version type) because that's what
    /// `UIDevice.current.systemVersion` / `ProcessInfo` actually hand you.
    public let osVersion: String

    /// Monotonic timestamp (seconds) when the process started — the
    /// earliest point your code can observe, typically captured from
    /// `ProcessInfo.processInfo.systemUptime` at the first opportunity
    /// your app gets to run (a static initializer or the top of `main`).
    public let processStart: TimeInterval

    /// Monotonic timestamp (seconds) marking the end of pre-main work:
    /// dyld closure rebuilding, fixups, and static initializers. This is
    /// the phase Apple's iOS 27 scheduler and preloading changes actually
    /// sped up. Must be >= processStart.
    public let preMainEnd: TimeInterval

    /// Monotonic timestamp (seconds) of the first rendered frame — the
    /// phase your own `didFinishLaunching` / `onAppear` code and any
    /// marketing/attribution SDKs live in. Must be >= preMainEnd.
    public let firstFrame: TimeInterval

    /// Fails to construct a sample whose timestamps are out of order,
    /// rather than silently producing a negative duration later.
    public init?(osVersion: String, processStart: TimeInterval, preMainEnd: TimeInterval, firstFrame: TimeInterval) {
        guard !osVersion.isEmpty,
              preMainEnd >= processStart,
              firstFrame >= preMainEnd else {
            return nil
        }
        self.osVersion = osVersion
        self.processStart = processStart
        self.preMainEnd = preMainEnd
        self.firstFrame = firstFrame
    }

    /// Total cold-launch duration: process start to first frame.
    public var coldLaunchDuration: TimeInterval { firstFrame - processStart }

    /// The phase Apple's OS-level launch optimizations actually touch.
    public var preMainDuration: TimeInterval { preMainEnd - processStart }

    /// The phase your own code (and vendor SDKs) own end to end.
    public var postMainDuration: TimeInterval { firstFrame - preMainEnd }

    /// A coarse cohort key — major OS version only ("26", "27") — which is
    /// the granularity that matters for a platform-level launch-time shift.
    /// Falls back to the full string if it isn't dot-separated numerics.
    public var majorVersionCohort: String {
        let major = osVersion.split(separator: ".", maxSplits: 1).first.map(String.init)
        return major ?? osVersion
    }
}

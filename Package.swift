// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LaunchCohort",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "LaunchCohort", targets: ["LaunchCohort"])
    ],
    targets: [
        .target(
            name: "LaunchCohort",
            path: "Sources/LaunchCohort"
        ),
        .testTarget(
            name: "LaunchCohortTests",
            dependencies: ["LaunchCohort"],
            path: "Tests/LaunchCohortTests"
        )
    ]
)

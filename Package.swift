// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexUsager",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS("15.0")],
    products: [.library(name: "UsageCore", targets: ["UsageCore"])],
    targets: [
        .target(name: "UsageCore", path: "Sources/UsageCore"),
        // Development-only executable. Releases use the Xcode Application target,
        // which embeds the Widget, Claude bridge, Info.plist and entitlements.
        .executableTarget(name: "CodexUsager", dependencies: ["UsageCore"], path: "Sources/CodexUsager", resources: [.process("Resources")]),
        .executableTarget(name: "ClaudeQuotaBridge", dependencies: ["UsageCore"], path: "Sources/ClaudeQuotaBridge"),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"], path: "Tests/UsageCoreTests")
    ]
)

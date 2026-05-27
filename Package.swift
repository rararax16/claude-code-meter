// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeCodeMeter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ClaudeCodeMeter", targets: ["ClaudeCodeMeter"])
    ],
    targets: [
        .executableTarget(
            name: "ClaudeCodeMeter",
            path: "Sources/ClaudeCodeMeter",
            swiftSettings: [
                // @testable import を効かせるために -parse-as-library にしておく。
                // executableTarget で SwiftUI @main を使う際の定番設定。
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "ClaudeCodeMeterTests",
            dependencies: ["ClaudeCodeMeter"],
            path: "Tests/ClaudeCodeMeterTests"
        )
    ]
)

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SparklePrompt",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SparklePrompt",
            path: "Sources/SparklePrompt"
        )
    ]
)

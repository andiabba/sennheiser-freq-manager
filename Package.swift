// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SennheiserFreqManager",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SennheiserFreqManager",
            path: "Sources/SennheiserFreqManager"
        )
    ]
)

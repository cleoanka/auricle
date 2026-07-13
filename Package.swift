// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Auricle",
    platforms: [
        .macOS("14.4")
    ],
    targets: [
        .executableTarget(
            name: "Auricle",
            path: "Sources/Auricle"
        ),
        .testTarget(
            name: "AuricleTests",
            dependencies: ["Auricle"],
            path: "Tests/AuricleTests"
        )
    ],
    swiftLanguageModes: [.v5]
)

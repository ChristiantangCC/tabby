// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Tabby",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Tabby", path: "Sources/Tabby")
    ]
)

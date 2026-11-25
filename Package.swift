// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KaffeeBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "KaffeeBar", path: "src")
    ]
)

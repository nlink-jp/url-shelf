// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "URLShelf",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "URLShelf",
            path: "Sources/URLShelf"
        ),
        .testTarget(
            name: "URLShelfTests",
            dependencies: ["URLShelf"],
            path: "Tests/URLShelfTests"
        ),
    ]
)

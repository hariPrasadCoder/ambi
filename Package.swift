// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Ambi",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Ambi", targets: ["Ambi"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "Ambi",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Ambi"
        )
    ]
)

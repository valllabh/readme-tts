// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ReadMe",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", branch: "main"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", .upToNextMajor(from: "3.31.3")),
        .package(url: "https://github.com/huggingface/swift-transformers.git", .upToNextMajor(from: "1.1.6")),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", .upToNextMajor(from: "2.8.0"))
    ],
    targets: [
        .target(
            name: "ReadMeCore",
            path: "Sources/ReadMeCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "ReadMe",
            dependencies: [
                "ReadMeCore",
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/ReadMe",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        // CommandLineTools ships no XCTest or Swift Testing module, so tests
        // run as a plain executable with assertions.
        .executableTarget(
            name: "ReadMeSelfTest",
            dependencies: ["ReadMeCore"],
            path: "Sources/ReadMeSelfTest",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)

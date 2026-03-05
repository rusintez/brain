// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "brain",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm/", from: "2.30.0"),
    ],
    targets: [
        .executableTarget(
            name: "brain",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ],
            path: "Sources"
        )
    ]
)

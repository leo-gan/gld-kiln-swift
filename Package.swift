// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "gld-kiln-swift",
    products: [
        .library(name: "Kiln", targets: ["Kiln"]),
        .executable(name: "gld-kilngen-swift", targets: ["gld-kilngen-swift"]),
        .executable(name: "kiln-bench", targets: ["kiln-bench"]),
        .executable(name: "kiln-example", targets: ["kiln-example"]),
    ],
    targets: [
        .target(
            name: "Kiln",
            path: "src",
            exclude: ["codegen"]
        ),
        .executableTarget(
            name: "gld-kilngen-swift",
            dependencies: ["Kiln"],
            path: "src/codegen"
        ),
        .executableTarget(
            name: "kiln-bench",
            dependencies: ["Kiln"],
            path: "benches"
        ),
        .executableTarget(
            name: "kiln-example",
            dependencies: ["Kiln"],
            path: "examples"
        ),
        .testTarget(
            name: "KilnTests",
            dependencies: ["Kiln"],
            path: "tests"
        ),
    ]
)

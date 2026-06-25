// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Junimo",
    products: [
        .library(name: "JunimoCore", targets: ["JunimoCore"]),
        .executable(name: "Junimo", targets: ["Junimo"])
    ],
    dependencies: [],
    targets: [
        .target(name: "JunimoCore"),
        .executableTarget(
            name: "Junimo",
            dependencies: ["JunimoCore"]
        ),
        .testTarget(
            name: "JunimoTests",
            dependencies: ["JunimoCore"]
        )
    ]
)

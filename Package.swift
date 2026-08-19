// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NiuLaiMarketPets",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "NiuLaiMarketPetsCore", targets: ["NiuLaiMarketPets"]),
        .executable(name: "NiuLaiMarketPets", targets: ["NiuLaiMarketPetsApp"]),
    ],
    targets: [
        .target(
            name: "NiuLaiMarketPets",
            path: "Sources/NiuLaiMarketPets",
            exclude: ["AppMain.swift", "AppUI.swift"]
        ),
        .executableTarget(
            name: "NiuLaiMarketPetsApp",
            dependencies: ["NiuLaiMarketPets"],
            path: "Sources/NiuLaiMarketPetsApp"
        ),
        .executableTarget(
            name: "NiuLaiMarketPetsTests",
            dependencies: ["NiuLaiMarketPets"],
            path: "Tests/NiuLaiMarketPetsTests"
        ),
    ]
)

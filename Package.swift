// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VisionProvider",
    platforms: [
        .macOS(.v14),
        .iOS(.v16),
        .tvOS(.v16),
    ],
    products: [
        .library(
            name: "VisionProvider",
            targets: ["VisionProvider"]
        ),
        .library(
            name: "Filmix",
            targets: ["Filmix"]
        ),
        .library(
            name: "Kinobase",
            targets: ["Kinobase"]
        ),
        .library(
            name: "Seasonvar",
            targets: ["Seasonvar"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.12.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.13.5"),
        .package(url: "https://github.com/resoul/flux.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "Filmix",
            dependencies: [
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ],
            path: "Sources/Filmix"
        ),
        .target(
            name: "Kinobase",
            dependencies: [
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ],
            path: "Sources/Kinobase"
        ),
        .target(
            name: "Seasonvar",
            dependencies: [
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ],
            path: "Sources/Seasonvar"
        ),
        .target(
            name: "VisionProvider",
            dependencies: [
                "Filmix",
                "Kinobase",
                "Seasonvar",
                .product(name: "Flux", package: "flux"),
            ],
            path: "Sources/VisionProvider"
        ),
    ]
)

// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Filmix",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
    ],
    products: [
        .library(
            name: "Filmix",
            targets: ["Filmix"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.12.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.13.5"),
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
    ]
)

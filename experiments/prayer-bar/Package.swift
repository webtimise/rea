// swift-tools-version:5.10

import PackageDescription

let package = Package(
    name: "PrayerBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PrayerBar", targets: ["PrayerBar"]),
        .library(name: "PrayerKit", targets: ["PrayerKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/batoulapps/adhan-swift", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "PrayerKit",
            dependencies: [.product(name: "Adhan", package: "adhan-swift")]
        ),
        .executableTarget(
            name: "PrayerBar",
            dependencies: ["PrayerKit", .product(name: "Adhan", package: "adhan-swift")]
        ),
        .testTarget(
            name: "PrayerKitTests",
            dependencies: ["PrayerKit", .product(name: "Adhan", package: "adhan-swift")]
        ),
    ]
)

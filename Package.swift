// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ArnmusicNativeAudio",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "ArnmusicNativeAudio",
            targets: ["ArnmusicNativeAudio"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "ArnmusicNativeAudio",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/ArnmusicNativeAudio"),
        .testTarget(
            name: "ArnmusicNativeAudioTests",
            dependencies: ["ArnmusicNativeAudio"],
            path: "ios/Tests/ArnmusicNativeAudioTests")
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ArnmusicNativeAudio",
    platforms: [.iOS(.v14)],
    products: [
        .library(
            name: "ArnmusicNativeAudio",
            targets: ["ExamplePlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "ExamplePlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/ExamplePlugin"),
        .testTarget(
            name: "ExamplePluginTests",
            dependencies: ["ExamplePlugin"],
            path: "ios/Tests/ExamplePluginTests")
    ]
)
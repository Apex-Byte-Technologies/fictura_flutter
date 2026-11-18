// swift-tools-version: 5.9

import PackageDescription

// The Fictura iOS SDK this package wraps. To build against a local checkout of
// fictura_ios (testing an unreleased change), set FICTURA_IOS_PATH to its folder.
let localIOS = Context.environment["FICTURA_IOS_PATH"].flatMap { $0.isEmpty ? nil : $0 }
let ficturaIOS: Package.Dependency = localIOS.map { .package(path: $0) }
    ?? .package(url: "https://github.com/Apex-Byte-Technologies/fictura_ios", from: "0.2.0")
// A path dependency is named after its folder; the URL one after the repository.
let ficturaIOSName = localIOS.map { String($0.split(separator: "/").last ?? "fictura_ios").lowercased() } ?? "fictura_ios"

let package = Package(
    name: "fictura_flutter",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "fictura-flutter", targets: ["fictura_flutter"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        ficturaIOS,
    ],
    targets: [
        .target(
            name: "fictura_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "FicturaSDK", package: ficturaIOSName),
            ]
        )
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FeishuImageHelper",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "FeishuImageHelper", targets: ["FeishuImageHelper"])],
    targets: [
        .target(name: "ImageHelperCore"),
        .executableTarget(name: "FeishuImageHelper", dependencies: ["ImageHelperCore"],
                          resources: [.copy("Resources")]),
        .executableTarget(name: "CoreChecks", dependencies: ["ImageHelperCore"], path: "Tests/CoreChecks")
    ],
    swiftLanguageVersions: [.v5]
)

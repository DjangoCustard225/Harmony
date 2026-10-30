// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Harmony",
    platforms: [.iOS("27.0")],
    products: [.library(name: "Harmony", targets: ["Harmony"])],
    dependencies: [.package(path: "Core")],
    targets: [
        .target(
            name: "Harmony", dependencies: [.product(name: "HarmonyCore", package: "Core")],
            path: "Harmony", exclude: ["Info.plist", "PrivacyInfo.xcprivacy", "Assets.xcassets"])
    ],
    swiftLanguageModes: [.v5]
)

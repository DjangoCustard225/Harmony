// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "HarmonyCore", platforms: [.iOS("27.0"), .macOS(.v14)],
    products: [.library(name: "HarmonyCore", targets: ["HarmonyCore"])],
    targets: [.target(name: "HarmonyCore"), .testTarget(name: "HarmonyCoreTests", dependencies: ["HarmonyCore"])],
    swiftLanguageModes: [.v5])

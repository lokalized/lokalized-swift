// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "lokalized-swift",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "Lokalized", targets: ["Lokalized"]),
        .executable(name: "LokalizedConformance", targets: ["LokalizedConformance"])
    ],
    dependencies: [],
    targets: [
        .target(name: "Lokalized", resources: [.copy("PrivacyInfo.xcprivacy")]),
        .target(name: "LokalizedConformanceSupport", dependencies: ["Lokalized"]),
        .executableTarget(name: "LokalizedConformance", dependencies: ["LokalizedConformanceSupport"]),
        .testTarget(name: "LokalizedTests", dependencies: ["Lokalized", "LokalizedConformanceSupport"])
    ],
    swiftLanguageModes: [.v6]
)

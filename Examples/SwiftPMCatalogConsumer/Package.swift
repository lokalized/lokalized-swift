// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftPMCatalogConsumer",
    platforms: [.iOS(.v15), .macOS(.v12)],
    dependencies: [.package(path: "../..")],
    targets: [.executableTarget(name: "SwiftPMCatalogConsumer", dependencies: [
        .product(name: "Lokalized", package: "lokalized-swift")
    ], resources: [.copy("Lokalized")], swiftSettings: [.defaultIsolation(MainActor.self)])],
    swiftLanguageModes: [.v6]
)

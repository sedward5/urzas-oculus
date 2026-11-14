// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "UrzasOculus",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UrzasOculusCore", targets: ["UrzasOculusCore"]),
        .executable(name: "UrzasOculus", targets: ["UrzasOculusApp"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .systemLibrary(name: "CZlib"),
        .target(name: "UrzasOculusCore", dependencies: ["CSQLite", "CZlib"]),
        .executableTarget(name: "UrzasOculusApp", dependencies: ["UrzasOculusCore"]),
        .testTarget(name: "UrzasOculusCoreTests", dependencies: ["UrzasOculusCore"])
    ],
    swiftLanguageVersions: [.v5]
)

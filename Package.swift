// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JuiceBar",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "JuiceBar", targets: ["JuiceBar"]),
    ],
    targets: [
        .executableTarget(
            name: "JuiceBar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .testTarget(
            name: "JuiceBarTests",
            dependencies: ["JuiceBar"]
        ),
    ]
)

// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "WebsiteImagePrep",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "WebsiteImagePrep", targets: ["WebsiteImagePrep"])
    ],
    targets: [
        .executableTarget(
            name: "WebsiteImagePrep",
            path: "Sources/WebsiteImagePrep"
        )
    ],
    swiftLanguageVersions: [.v5]
)

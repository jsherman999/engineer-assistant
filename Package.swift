// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EngineerAssistant",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "EngineerAssistant", targets: ["EngineerAssistant"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.13.0")
    ],
    targets: [
        .executableTarget(
            name: "EngineerAssistant",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/EngineerAssistant"
        ),
        .testTarget(
            name: "EngineerAssistantTests",
            dependencies: ["EngineerAssistant"],
            path: "Tests/EngineerAssistantTests"
        ),
    ]
)

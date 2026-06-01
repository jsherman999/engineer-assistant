// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EngineerAssistant",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "EngineerAssistant", targets: ["EngineerAssistant"])
    ],
    targets: [
        .executableTarget(
            name: "EngineerAssistant",
            path: "Sources/EngineerAssistant"
        ),
        .testTarget(
            name: "EngineerAssistantTests",
            dependencies: ["EngineerAssistant"],
            path: "Tests/EngineerAssistantTests"
        ),
    ]
)

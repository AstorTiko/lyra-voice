// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LyraVoice",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "LyraVoiceCore", targets: ["LyraVoiceCore"]),
        .executable(name: "LyraVoice", targets: ["LyraVoiceApp"])
    ],
    targets: [
        .target(
            name: "LyraVoiceCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "LyraVoiceApp",
            dependencies: ["LyraVoiceCore"]
        ),
        .executableTarget(
            name: "LyraVoiceCoreSmokeTests",
            dependencies: ["LyraVoiceCore"]
        ),
        .executableTarget(
            name: "CorpusBenchmark",
            dependencies: ["LyraVoiceCore"]
        )
    ]
)

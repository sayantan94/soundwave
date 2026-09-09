// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SoundWave",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "SoundWave", targets: ["SoundWave"])],
    targets: [
        .target(name: "CAudioRing"),
        .target(name: "SoundWaveCore"),
        .executableTarget(name: "SoundWave", dependencies: ["SoundWaveCore", "CAudioRing"]),
        .testTarget(name: "SoundWaveCoreTests", dependencies: ["SoundWaveCore", "CAudioRing"])
    ]
)

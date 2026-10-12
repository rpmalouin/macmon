// swift-tools-version:5.9
import PackageDescription

// The app: a SwiftUI panel on the sampler behind `ffi/`, built by `scripts/app-build.sh`.
//
// `CMacmon` is the clang shim that carries `ffi/include/macmon.h` into Swift; the archive itself
// is linked by the build script, which passes `-L`/`-l`/framework flags to the link step.
let package = Package(
  name: "Macmon",
  platforms: [.macOS(.v14)],
  targets: [
    .target(name: "CMacmon", path: "Sources/CMacmon"),
    .target(name: "MacmonCore", dependencies: ["CMacmon"], path: "Sources/MacmonCore"),
    .executableTarget(name: "MacmonApp", dependencies: ["MacmonCore"], path: "Sources/MacmonApp"),
    .testTarget(name: "MacmonCoreTests", dependencies: ["MacmonCore"], path: "Tests/MacmonCoreTests"),
  ]
)

// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "MiNoteCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [.library(name: "MiNoteCore", targets: ["MiNoteCore"])],
    targets: [.target(name: "MiNoteCore"), .testTarget(name: "MiNoteCoreTests", dependencies: ["MiNoteCore"], resources: [.copy("Fixtures/PortableInk")])]
)

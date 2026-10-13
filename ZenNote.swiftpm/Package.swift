// swift-tools-version: 5.9
import PackageDescription
#if canImport(AppleProductTypes)
import AppleProductTypes
#endif

// AppleProductTypes is provided by Swift Playgrounds. Other hosts build only
// the Foundation-based core and its tests; they cannot build the iPad UI.
var products: [Product] = [
    .library(name: "ZenNoteCore", targets: ["ZenNoteCore"])
]
var targets: [Target] = [
    .target(name: "ZenNoteCore", path: "Sources/ZenNoteCore"),
    .testTarget(name: "ZenNoteCoreTests", dependencies: ["ZenNoteCore"], path: "Tests/ZenNoteCoreTests")
]
#if canImport(AppleProductTypes)
products.insert(.iOSApplication(
    name: "Zen Note",
    targets: ["AppModule"],
    bundleIdentifier: "personal.zennote.prototype",
    displayVersion: "0.2.1",
    bundleVersion: "3",
    appIcon: .placeholder(icon: .openBook),
    accentColor: .presetColor(.teal),
    supportedDeviceFamilies: [.pad],
    supportedInterfaceOrientations: [.landscapeLeft, .landscapeRight],
    additionalInfoPlistContentFilePath: "AppInfo.plist"
), at: 0)
targets.append(.executableTarget(
    name: "AppModule", dependencies: ["ZenNoteCore"], path: "Sources/AppModule"
))
#endif

let package = Package(
    name: "ZenNote",
    platforms: [.iOS("16.0")],
    products: products,
    targets: targets,
    swiftLanguageVersions: [.v5]
)

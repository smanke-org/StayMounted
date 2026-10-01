// swift-tools-version: 6.2
import PackageDescription

// STAYMOUNTED_APPSTORE=1 builds the Mac App Store flavour: the self-updater is compiled
// out (App Review guideline 2.4.5), and build_app.sh signs it sandboxed. Everything else
// is shared, so the GitHub build is always exercising the code that will ship to the store.
let appStore = Context.environment["STAYMOUNTED_APPSTORE"] == "1"

let package = Package(
    name: "StayMounted",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "StayMountedKit",
            linkerSettings: [.linkedFramework("NetFS")]
        ),
        .executableTarget(
            name: "StayMounted",
            dependencies: ["StayMountedKit"],
            swiftSettings: appStore ? [.define("APPSTORE")] : []
        ),
        .testTarget(name: "StayMountedKitTests", dependencies: ["StayMountedKit"]),
    ]
)

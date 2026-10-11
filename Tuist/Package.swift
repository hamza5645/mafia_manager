// swift-tools-version: 5.9
import PackageDescription

#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    productTypes: [:],
    // ConvexMobile's Rust XCFramework ships an arm64-only simulator slice, so the
    // dependencies' x86_64 simulator slices are never linked.
    baseSettings: .settings(base: ["EXCLUDED_ARCHS[sdk=iphonesimulator*]": "x86_64"]),
    targetSettings: [
        // Tuist renames this product to ConvexMobileWrapper.framework while the
        // module inside stays ConvexMobile, which breaks `import ConvexMobile`.
        "ConvexMobile": .settings(base: ["PRODUCT_NAME": "ConvexMobile"]),
    ]
)
#endif

// Exact pins: clerk-ios ships breaking changes in minor and patch releases, and the
// vendored ClerkKitConvex bridge depends on its token APIs. Bump deliberately, re-test
// sign-up, sign-in and token refresh, and record the bump in docs/SESSION_CHANGES.md.
let package = Package(
    name: "mafia_manager",
    dependencies: [
        .package(url: "https://github.com/get-convex/convex-swift", exact: "0.8.1"),
        .package(url: "https://github.com/clerk/clerk-ios", exact: "1.1.1"),
    ]
)

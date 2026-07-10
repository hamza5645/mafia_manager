// swift-tools-version: 5.9
import PackageDescription

#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    productTypes: [:],
    targetSettings: [
        // Tuist renames this product to ConvexMobileWrapper.framework while the
        // module inside stays ConvexMobile, which breaks `import ConvexMobile`.
        "ConvexMobile": .settings(base: ["PRODUCT_NAME": "ConvexMobile"]),
    ]
)
#endif

let package = Package(
    name: "mafia_manager",
    dependencies: [
        .package(url: "https://github.com/get-convex/convex-swift", from: "0.8.0"),
        .package(url: "https://github.com/clerk/clerk-ios", from: "1.0.0"),
    ]
)

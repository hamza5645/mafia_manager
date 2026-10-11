import ProjectDescription

// Fails the build when a MAFIA_* value is missing. In Release it also requires the
// production backend: a pk_live_ Clerk key, a .convex.cloud host other than the
// development one in Debug.xcconfig, and a Clerk frontend host outside .accounts.dev.
// Local profiling builds that point Release at dev pass MAFIA_ALLOW_NONPROD_RELEASE=YES.
let verifyBackendConfig = """
set -eu
fail() { echo "error: $1"; exit 1; }
[ -n "${MAFIA_CONVEX_HOST:-}" ] || fail "MAFIA_CONVEX_HOST is empty. Set it in Configuration/*.xcconfig and run tuist generate."
[ -n "${MAFIA_CLERK_PUBLISHABLE_KEY:-}" ] || fail "MAFIA_CLERK_PUBLISHABLE_KEY is empty. Set it in Configuration/*.xcconfig and run tuist generate."
[ -n "${MAFIA_CLERK_FRONTEND_HOST:-}" ] || fail "MAFIA_CLERK_FRONTEND_HOST is empty. Set it in Configuration/*.xcconfig and run tuist generate."
[ "$CONFIGURATION" = "Release" ] || exit 0
if [ "${MAFIA_ALLOW_NONPROD_RELEASE:-NO}" = "YES" ]; then
  echo "warning: MAFIA_ALLOW_NONPROD_RELEASE=YES, so the production backend checks are skipped. Never ship this build."
  exit 0
fi
case "$MAFIA_CLERK_PUBLISHABLE_KEY" in
  pk_live_*) ;;
  *) fail "Release needs the production Clerk key (pk_live_) in Configuration/Production.xcconfig." ;;
esac
case "$MAFIA_CONVEX_HOST" in
  *.convex.cloud) ;;
  *) fail "Release needs a .convex.cloud host in Configuration/Production.xcconfig." ;;
esac
dev_host=$(sed -n 's/^MAFIA_CONVEX_HOST[[:space:]]*=[[:space:]]*\\([^[:space:]]*\\).*/\\1/p' "$SRCROOT/Configuration/Debug.xcconfig")
[ "$MAFIA_CONVEX_HOST" != "$dev_host" ] || fail "Release points at the development Convex host ($dev_host). Use the production host in Configuration/Production.xcconfig."
case "$MAFIA_CLERK_FRONTEND_HOST" in
  *.accounts.dev) fail "Release needs the production Clerk frontend host, not $MAFIA_CLERK_FRONTEND_HOST." ;;
esac
"""

let project = Project(
    name: "mafia_manager",
    settings: .settings(
        base: [
            "DEVELOPMENT_TEAM": "5GH22BAXAU",
            "CODE_SIGN_STYLE": "Automatic",
            // ConvexMobile's Rust XCFramework ships an arm64-only simulator slice.
            "EXCLUDED_ARCHS[sdk=iphonesimulator*]": "x86_64",
            "MARKETING_VERSION": "5.0",
            "CURRENT_PROJECT_VERSION": "11",
            "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
            "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
            "STRING_CATALOG_GENERATE_SYMBOLS": "NO",
            "SWIFT_EMIT_LOC_STRINGS": "NO",
        ]
    ),
    targets: [
        .target(
            name: "mafia_manager",
            destinations: [.iPhone, .iPad],
            product: .app,
            bundleId: "com.hamza5645.mafia",
            deploymentTargets: .iOS("18.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "CFBundleDisplayName": "Mafia",
                "MafiaConvexHost": "$(MAFIA_CONVEX_HOST)",
                "MafiaClerkPublishableKey": "$(MAFIA_CLERK_PUBLISHABLE_KEY)",
                "ITSAppUsesNonExemptEncryption": false,
                "UIApplicationSupportsIndirectInputEvents": true,
                "UILaunchScreen": ["UIColorName": "LaunchBackground"],
                "UISupportedInterfaceOrientations": [
                    "UIInterfaceOrientationPortrait",
                ],
                "UISupportedInterfaceOrientations~ipad": [
                    "UIInterfaceOrientationPortrait",
                    "UIInterfaceOrientationPortraitUpsideDown",
                    "UIInterfaceOrientationLandscapeLeft",
                    "UIInterfaceOrientationLandscapeRight",
                ],
            ]),
            sources: [
                "App/**",
                "Core/**",
                "Features/**",
                "Vendor/clerk-convex-swift/Sources/ClerkKitConvex/**",
            ],
            resources: [
                "Assets.xcassets",
                "Resources/**",
                "PrivacyInfo.xcprivacy",
            ],
            entitlements: .dictionary([
                "com.apple.developer.associated-domains": ["webcredentials:$(MAFIA_CLERK_FRONTEND_HOST)"],
            ]),
            scripts: [
                .pre(
                    script: verifyBackendConfig,
                    name: "Verify backend config",
                    inputPaths: ["$(SRCROOT)/Configuration/Debug.xcconfig"],
                    basedOnDependencyAnalysis: false
                ),
            ],
            dependencies: [
                .external(name: "ConvexMobile"),
                .external(name: "ClerkKit"),
            ],
            settings: .settings(
                base: [
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
                    "ENABLE_PREVIEWS": "YES",
                    "SWIFT_VERSION": "5",
                    // Swift 6 diagnostics as warnings; the Swift 6 language mode is a later step (PA-81).
                    "SWIFT_STRICT_CONCURRENCY": "complete",
                ],
                configurations: [
                    .debug(
                        name: "Debug",
                        settings: [
                            // Flags slow type-checking (SetupView.body took over a second).
                            "OTHER_SWIFT_FLAGS": "$(inherited) -Xfrontend -warn-long-function-bodies=200 -Xfrontend -warn-long-expression-type-checking=200",
                        ],
                        xcconfig: "Configuration/Debug.xcconfig"
                    ),
                    .release(
                        name: "Release",
                        settings: [
                            "SWIFT_OPTIMIZATION_LEVEL": "-O",
                            "SWIFT_COMPILATION_MODE": "wholemodule",
                            "DEAD_CODE_STRIPPING": "YES",
                            "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
                        ],
                        xcconfig: "Configuration/Production.xcconfig"
                    ),
                ]
            )
        ),
        .target(
            name: "mafia_managerTests",
            destinations: [.iPhone, .iPad],
            product: .unitTests,
            bundleId: "com.hamza5645.mafiaTests",
            deploymentTargets: .iOS("18.0"),
            sources: [
                "mafia_managerTests/**",
            ],
            // Shared backend fixtures (rules parity, contract snapshots), copied flat into the bundle.
            resources: [
                "tests/fixtures/**/*.json",
            ],
            dependencies: [
                .target(name: "mafia_manager"),
            ],
            settings: .settings(
                base: [
                    "SWIFT_STRICT_CONCURRENCY": "complete",
                ]
            )
        ),
    ]
)

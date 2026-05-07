import ProjectDescription

let project = Project(
    name: "mafia_manager",
    settings: .settings(
        base: [
            "DEVELOPMENT_TEAM": "5GH22BAXAU",
            "CODE_SIGN_STYLE": "Automatic",
            "MARKETING_VERSION": "5.0",
            "CURRENT_PROJECT_VERSION": "10",
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
                "ITSAppUsesNonExemptEncryption": false,
                "UIApplicationSupportsIndirectInputEvents": true,
                "UILaunchScreen": [:],
                "UISupportedInterfaceOrientations": [
                    "UIInterfaceOrientationPortrait",
                    "UIInterfaceOrientationLandscapeLeft",
                    "UIInterfaceOrientationLandscapeRight",
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
            ],
            resources: [
                "Assets.xcassets",
                "Resources/**",
                "PrivacyInfo.xcprivacy",
            ],
            dependencies: [
                .external(name: "ConvexMobile"),
                .external(name: "ClerkKit"),
                .external(name: "ClerkKitUI"),
                .external(name: "ClerkConvex"),
            ],
            settings: .settings(
                base: [
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
                    "ENABLE_PREVIEWS": "YES",
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
            dependencies: [
                .target(name: "mafia_manager"),
            ]
        ),
    ]
)

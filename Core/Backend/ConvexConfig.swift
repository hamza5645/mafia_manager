import Foundation

enum ConvexConfig {
    static let apiContractVersion = 3
    #if DEBUG
    static let deploymentURL = "https://energized-herring-345.eu-west-1.convex.cloud"

    static let clerkPublishableKey = "pk_test_c3RyaWtpbmctZWxmLTIyLmNsZXJrLmFjY291bnRzLmRldiQ"

    #else
    static let deploymentURL = "https://\(productionValue("MafiaProductionConvexHost"))"
    static let clerkPublishableKey = productionValue("MafiaProductionClerkPublishableKey")

    private static func productionValue(_ key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.contains("$(") else {
            fatalError("Missing production backend configuration. Configure Production.xcconfig and regenerate with Tuist.")
        }
        return value
    }
    #endif

    static var hasConfiguredClerkKey: Bool {
        clerkPublishableKey.hasPrefix("pk_")
    }
}

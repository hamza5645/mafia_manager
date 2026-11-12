import Foundation

/// Backend values come from `Configuration/Debug.xcconfig` (Debug) or
/// `Configuration/Production.xcconfig` (Release) through Info.plist.
enum ConvexConfig {
    static let apiContractVersion = 5

    static let deploymentURL = deploymentURL(environment: ProcessInfo.processInfo.environment)

    /// Debug builds accept a full `http(s)://` URL in the `MAFIA_CONVEX_URL`
    /// environment variable (live tests against a local or preview backend).
    /// Release builds ignore it.
    static func deploymentURL(environment: [String: String]) -> String {
        #if DEBUG
        if let override = environment["MAFIA_CONVEX_URL"],
           let url = URL(string: override), url.scheme == "http" || url.scheme == "https", url.host != nil {
            return override
        }
        #endif
        return "https://\(infoValue("MafiaConvexHost"))"
    }

    static let clerkPublishableKey: String = {
        let key = infoValue("MafiaClerkPublishableKey")
        #if !DEBUG
        guard key.hasPrefix("pk_live_") else {
            fatalError("Release builds require a production Clerk publishable key (pk_live_) in Production.xcconfig.")
        }
        #endif
        return key
    }()

    private static func infoValue(_ key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.contains("$(") else {
            fatalError("Missing \(key) in Info.plist. Set it in Configuration/*.xcconfig and regenerate with Tuist.")
        }
        return value
    }
}

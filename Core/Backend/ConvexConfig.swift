import Foundation

/// Backend values come from `Configuration/Debug.xcconfig` (Debug) or
/// `Configuration/Production.xcconfig` (Release) through Info.plist.
enum ConvexConfig {
    static let apiContractVersion = 4
    static let deploymentURL = "https://\(infoValue("MafiaConvexHost"))"

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

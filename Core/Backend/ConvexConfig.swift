import Foundation

enum ConvexConfig {
    static let deploymentURL = "https://energized-herring-345.eu-west-1.convex.cloud"

    static let clerkPublishableKey = "pk_test_c3RyaWtpbmctZWxmLTIyLmNsZXJrLmFjY291bnRzLmRldiQ"

    static var hasConfiguredClerkKey: Bool {
        clerkPublishableKey.hasPrefix("pk_")
    }
}

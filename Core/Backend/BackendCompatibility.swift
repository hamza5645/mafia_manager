import Combine
import Foundation

/// Whether this build's api_contract is still accepted by the backend.
/// Blocks only online features, and only on an explicit mismatch.
@MainActor
final class BackendCompatibility: ObservableObject {
    static let shared = BackendCompatibility()
    static let updateMessage = "This version of Mafia is too old for online play. Update the app to keep playing online."

    @Published private(set) var updateRequired = false

    /// Returns the backend's `min_client_contract`.
    private let fetchMinClientContract: @MainActor () async throws -> Int
    private var isChecking = false
    private var hasChecked = false

    init(fetchMinClientContract: (@MainActor () async throws -> Int)? = nil) {
        self.fetchMinClientContract = fetchMinClientContract ?? {
            try await ConvexService.shared.query("health:check", as: HealthCheck.self).minClientContract
        }
    }

    /// Calls `health:check` once per launch, off the critical path. An error
    /// or a timeout never blocks anything; a later call tries again until one
    /// check succeeds.
    func checkOnce() async {
        guard !hasChecked, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        guard let minClientContract = try? await fetchMinClientContract() else { return }
        hasChecked = true
        if ConvexConfig.apiContractVersion < minClientContract {
            updateRequired = true
        }
    }

    /// A response the app cannot decode after a confirming retry means the backend moved on.
    func markUpdateRequired() {
        updateRequired = true
    }

    private struct HealthCheck: Decodable {
        let minClientContract: Int

        enum CodingKeys: String, CodingKey {
            case minClientContract = "min_client_contract"
        }
    }
}

import Combine
import Foundation
import ClerkConvex
import ClerkKit
import ConvexMobile

@MainActor
final class ConvexService {
    static let shared = ConvexService()

    let client: ConvexClient

    private let authProvider: ClerkConvexAuthProvider?
    private let signOutHandler: (() async -> Void)?

    private init() {
        if ConvexConfig.hasConfiguredClerkKey {
            Clerk.configure(publishableKey: ConvexConfig.clerkPublishableKey)
            let provider = ClerkConvexAuthProvider()
            let authenticatedClient = ConvexClientWithAuth(
                deploymentUrl: ConvexConfig.deploymentURL,
                authProvider: provider
            )
            provider.bind(client: authenticatedClient)
            self.authProvider = provider
            self.client = authenticatedClient
            self.signOutHandler = { [weak authenticatedClient] in
                await authenticatedClient?.logout()
            }
        } else {
            self.authProvider = nil
            self.client = ConvexClient(deploymentUrl: ConvexConfig.deploymentURL)
            self.signOutHandler = nil
        }

        print("✅ [ConvexService] Initialized")
    }

    func query<T: Decodable>(
        _ name: String,
        with args: [String: ConvexEncodable?]? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        try await client.subscribe(to: name, with: stripNilArgs(args), yielding: type)
            .first()
            .async()
    }

    func mutation<T: Decodable>(
        _ name: String,
        with args: [String: ConvexEncodable?]? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        try await client.mutation(name, with: stripNilArgs(args))
    }

    func mutation(
        _ name: String,
        with args: [String: ConvexEncodable?]? = nil
    ) async throws {
        try await client.mutation(name, with: stripNilArgs(args))
    }

    func subscribe<T: Decodable>(
        _ name: String,
        with args: [String: ConvexEncodable?]? = nil,
        as type: T.Type = T.self
    ) -> AnyPublisher<T, ClientError> {
        client.subscribe(to: name, with: stripNilArgs(args), yielding: type)
    }

    // Convex's `v.optional(...)` accepts undefined/missing keys but rejects JSON `null`.
    // convex-swift encodes Optional.none as `null`, so we drop nil entries before sending.
    private func stripNilArgs(_ args: [String: ConvexEncodable?]?) -> [String: ConvexEncodable?]? {
        guard let args else { return nil }
        return args.filter { $0.value != nil }
    }

    func logout() async {
        await signOutHandler?()
    }
}

private extension Publisher where Failure: Error {
    func async() async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = first().sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        continuation.resume(throwing: error)
                    }
                    cancellable?.cancel()
                },
                receiveValue: { value in
                    continuation.resume(returning: value)
                    cancellable?.cancel()
                }
            )
        }
    }
}

import Combine
import Foundation
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
            // ConvexClientWithAuth(deploymentUrl:authProvider:) calls
            // provider.bind(client: self) inside its convenience init
            // (ConvexClientWithAuth+Clerk.swift), so a second bind here
            // would just cancel and restart the session-sync task.
            let authenticatedClient = ConvexClientWithAuth(
                deploymentUrl: ConvexConfig.deploymentURL,
                authProvider: provider
            )
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

    /// Force-installs the Convex FFI auth callback against the current Clerk
    /// session. Required after a fresh sign-up verification or password
    /// reset: those flows emit `.signUpCompleted` / `.signInCompleted`, which
    /// the patched `ClerkConvexAuthProvider` handles asynchronously on its
    /// own session-sync task. If we fire the next Convex mutation from the
    /// call-site task before that task runs, the mutation hangs in the Rust
    /// FFI layer waiting for an auth token. Calling `loginFromCache()` here
    /// installs the callback synchronously on the call-site task; the SDK
    /// task's later run is a redundant no-op.
    func refreshAuthFromClerk() async throws {
        guard let authed = client as? ConvexClientWithAuth<String> else { return }
        // setActive() doesn't synchronously flip Clerk.session.status to
        // .active; refreshClient() does. On a slow network the flip can lag
        // a few hundred ms, so poll briefly with a hard ceiling before
        // calling loginFromCache (which throws noActiveSession otherwise).
        let deadline = Date().addingTimeInterval(5.0)
        while Clerk.shared.session?.status != .active && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        _ = try await authed.loginFromCache().get()
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

import Combine
import Foundation
import ClerkKit
import ConvexMobile

@MainActor
final class ConvexService {
    static let shared = ConvexService()

    let client: ConvexClientWithAuth<String>

    /// Returns this device's guest proof, or nil. Read on every request and
    /// sent as `guest_secret_hash` unless the caller passes one explicitly.
    var guestProofProvider: (@MainActor () -> String?)?

    private init() {
        Clerk.configure(publishableKey: ConvexConfig.clerkPublishableKey)
        // The convenience init binds the provider to this client, which
        // starts its Clerk session sync.
        client = ConvexClientWithAuth(
            deploymentUrl: ConvexConfig.deploymentURL,
            authProvider: ClerkConvexAuthProvider()
        )
        print("✅ [ConvexService] Initialized")
    }

    func query<T: Decodable>(
        _ name: String,
        with args: [String: ConvexEncodable?] = [:],
        as type: T.Type = T.self
    ) async throws -> T {
        do {
            return try await client.subscribe(to: name, with: prepare(args), yielding: type)
                .first()
                .async()
        } catch {
            if error is CancellationError { throw error }
            throw BackendError(error)
        }
    }

    func mutation<T: Decodable>(
        _ name: String,
        with args: [String: ConvexEncodable?] = [:],
        as type: T.Type = T.self
    ) async throws -> T {
        do {
            return try await client.mutation(name, with: prepare(args))
        } catch {
            if error is CancellationError { throw error }
            throw BackendError(error)
        }
    }

    /// For mutations whose result the caller ignores. convex-swift's own
    /// result-less overload decodes `String?`, which fails for mutations that
    /// return an object (e.g. `phases:advancePhase`).
    func mutation(
        _ name: String,
        with args: [String: ConvexEncodable?] = [:]
    ) async throws {
        let _: IgnoredResult = try await mutation(name, with: args)
    }

    private struct IgnoredResult: Decodable {
        init(from decoder: Decoder) throws {}
    }

    func subscribe<T: Decodable>(
        _ name: String,
        with args: [String: ConvexEncodable?] = [:],
        as type: T.Type = T.self
    ) -> AnyPublisher<T, ClientError> {
        client.subscribe(to: name, with: prepare(args), yielding: type)
    }

    // Convex's `v.optional(...)` accepts undefined/missing keys but rejects JSON `null`.
    // convex-swift encodes Optional.none as `null`, so we drop nil entries before sending.
    // The server derives the caller from Clerk auth or the guest proof added here.
    private func prepare(_ args: [String: ConvexEncodable?]) -> [String: ConvexEncodable?] {
        var prepared = args.filter { $0.value != nil }
        if prepared["guest_secret_hash"] == nil,
           let proof = guestProofProvider?(), !proof.isEmpty {
            prepared["guest_secret_hash"] = proof
        }
        return prepared
    }

    func logout() async {
        await client.logout()
    }

    /// Installs the current Clerk session's token in Convex on the calling
    /// task. The provider's session-sync task does the same when Clerk
    /// reports a new session, but on its own task, so a mutation sent right
    /// after sign-in could otherwise wait in the Rust FFI layer for a token.
    func refreshAuthFromClerk() async throws {
        // Clerk can report the new session as active a few hundred ms after
        // setActive returns, so poll briefly before loginFromCache (which
        // throws noActiveSession otherwise).
        let deadline = Date().addingTimeInterval(5.0)
        while (!Clerk.shared.isLoaded || Clerk.shared.session?.status != .active) && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        _ = try await client.loginFromCache().get()
    }
}

/// Sends an Encodable value as a Convex argument using its Codable keys, so
/// nested objects are not listed field by field a second time.
struct ConvexJSON: ConvexEncodable {
    private let json: String

    init<T: Encodable>(_ value: T) throws {
        json = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    func convexEncode() throws -> String {
        json
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

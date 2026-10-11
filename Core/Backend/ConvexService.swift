import Combine
import Foundation
import ClerkKit
// ConvexMobile predates Sendable; its client holds only the Rust FFI client and Combine subjects.
@preconcurrency import ConvexMobile

/// The websocket's state as reported by ConvexMobile. A hint only: states can be dropped.
enum ConvexConnectionState: Sendable, Equatable {
    case connecting
    case connected
}

@MainActor
final class ConvexService {
    static let shared = ConvexService()

    // nonisolated: default arguments are evaluated outside the main actor.
    nonisolated static let defaultQueryTimeout: Duration = .seconds(15)
    nonisolated static let interactiveMutationTimeout: Duration = .seconds(12)

    let client: ConvexClientWithAuth<String>

    /// Fed from ConvexMobile's `watchWebSocketState()`.
    let connectionState = CurrentValueSubject<ConvexConnectionState, Never>(.connected)
    private var webSocketStateObserver: AnyCancellable?

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
        // Before any other call: the state subject does not replay. States arrive on
        // FFI threads; hop to main first, since every closure here is main-actor.
        webSocketStateObserver = client.watchWebSocketState()
            .receive(on: DispatchQueue.main)
            .map { $0 == .connected ? ConvexConnectionState.connected : .connecting }
            .sink { [connectionState] in connectionState.send($0) }
        print("✅ [ConvexService] Initialized")
    }

    /// One value of a query. A timeout throws a network `BackendError` with
    /// `isTimeout`; cancelling the calling task ends the subscription.
    func query<T: Decodable>(
        _ name: String,
        with args: [String: ConvexEncodable?] = [:],
        as type: T.Type = T.self,
        timeout: Duration? = ConvexService.defaultQueryTimeout
    ) async throws -> T {
        do {
            // Decoded here, not by convex-swift off the main actor (see `mutation`).
            let result = try await Self.firstValue(
                of: client.subscribe(to: name, with: prepare(args), yielding: ConvexResultJSON.self),
                timeout: timeout,
                timeoutError: BackendError(timedOut: BackendError.network)
            )
            return try JSONDecoder().decode(T.self, from: JSONEncoder().encode(result))
        } catch {
            if error is CancellationError { throw error }
            throw BackendError(error)
        }
    }

    /// A timeout throws `BackendError.stillSending` with `isTimeout`: the
    /// mutation may still be applied, so callers must not report a failure or
    /// retry it blindly. Cancelling the calling task does not stop the call.
    func mutation<T: Decodable>(
        _ name: String,
        with args: [String: ConvexEncodable?] = [:],
        as type: T.Type = T.self,
        timeout: Duration? = nil
    ) async throws -> T {
        let client = client
        do {
            // convex-swift encodes the arguments and decodes the result off the
            // main actor, where the app's main-actor-isolated conformances must
            // not run. Both cross as plain JSON, encoded and decoded here instead.
            let arguments = try EncodedArguments(prepare(args))
            let result: ConvexResultJSON
            if let timeout {
                result = try await Self.withTimeout(timeout, error: BackendError(timedOut: BackendError.stillSending)) {
                    try await client.mutation(name, with: arguments.forClient)
                }
            } else {
                result = try await client.mutation(name, with: arguments.forClient)
            }
            return try JSONDecoder().decode(T.self, from: JSONEncoder().encode(result))
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
        with args: [String: ConvexEncodable?] = [:],
        timeout: Duration? = nil
    ) async throws {
        let _: IgnoredResult = try await mutation(name, with: args, timeout: timeout)
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

// MARK: - Time limits

extension ConvexService {
    /// The first value of `publisher`, raced against `timeout` (nil: no limit),
    /// after which it throws `timeoutError`. Whatever finishes the wait,
    /// including cancelling the calling task, cancels the subscription.
    /// Runs on the caller's actor (`nonsending`), so the publisher never changes actors.
    nonisolated(nonsending) static func firstValue<T: Sendable, Failure: Error>(
        of publisher: AnyPublisher<T, Failure>,
        timeout: Duration?,
        timeoutError: Error
    ) async throws -> T {
        let race = FirstResult<T>()
        subscribe(race, toFirstOf: publisher)
        if let timeout {
            race.startTimer(timeout, error: timeoutError)
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { race.install($0) }
        } onCancel: {
            race.resolve(.failure(CancellationError()))
        }
    }

    /// Resolves `race` with the publisher's first value or failure and unsubscribes when
    /// the race ends. Nonisolated and synchronous, so these closures carry no actor
    /// isolation: convex-swift calls them on its own threads.
    nonisolated private static func subscribe<T: Sendable, Failure: Error>(
        _ race: FirstResult<T>,
        toFirstOf publisher: AnyPublisher<T, Failure>
    ) {
        let subscription = publisher.first().sink(
            receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    race.resolve(.failure(error))
                case .finished:
                    // Only reached without a value if the upstream ended early.
                    race.resolve(.failure(ClientError.InternalError(msg: "Query ended without a value")))
                }
            },
            receiveValue: { race.resolve(.success($0)) }
        )
        race.onFinish { subscription.cancel() }
    }

    /// Runs `operation` in an unstructured task and returns its result, or
    /// throws `error` once `timeout` passes. The operation keeps running after
    /// a timeout (an FFI call cannot be cancelled) and its late result is
    /// dropped. Not `withThrowingTaskGroup`: that waits for every child.
    nonisolated static func withTimeout<T: Sendable>(
        _ timeout: Duration,
        error: Error,
        operation: sending @escaping () async throws -> T
    ) async throws -> T {
        let race = FirstResult<T>()
        Task {
            do {
                race.resolve(.success(try await operation()))
            } catch {
                race.resolve(.failure(error))
            }
        }
        race.startTimer(timeout, error: error)
        return try await withCheckedThrowingContinuation { race.install($0) }
    }
}

/// Resumes one continuation with whichever result arrives first; later
/// results are dropped and the cleanups (unsubscribe, stop the timer) run once.
/// Results can arrive on any thread.
nonisolated private final class FirstResult<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var result: Result<T, Error>?
    private var cleanups: [() -> Void] = []

    func install(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func resolve(_ newResult: Result<T, Error>) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = newResult
        let continuation = self.continuation
        self.continuation = nil
        let cleanups = self.cleanups
        self.cleanups = []
        lock.unlock()
        cleanups.forEach { $0() }
        continuation?.resume(with: newResult)
    }

    func onFinish(_ cleanup: @escaping () -> Void) {
        lock.lock()
        if result == nil {
            cleanups.append(cleanup)
            lock.unlock()
        } else {
            lock.unlock()
            cleanup()
        }
    }

    func startTimer(_ timeout: Duration, error: Error) {
        let timer = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            self?.resolve(.failure(error))
        }
        onFinish { timer.cancel() }
    }
}

/// A Convex function result as plain JSON, with a nonisolated conformance so
/// convex-swift can decode it off the main actor.
nonisolated private enum ConvexResultJSON: Codable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([ConvexResultJSON])
    case object([String: ConvexResultJSON])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ConvexResultJSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: ConvexResultJSON].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// Function arguments as the JSON strings convex-swift sends. Unlike
/// `ConvexEncodable` values they are Sendable, so a call can leave the main actor.
nonisolated private struct EncodedArguments: Sendable {
    private let json: [String: String]

    /// Encodes on the caller's actor, which owns the values' conformances.
    init(_ args: [String: ConvexEncodable?]) throws {
        json = try args.compactMapValues { try $0?.convexEncode() }
    }

    var forClient: [String: ConvexEncodable?] {
        json.mapValues { Encoded(json: $0) as ConvexEncodable? }
    }

    nonisolated private struct Encoded: ConvexEncodable {
        let json: String

        func convexEncode() throws -> String {
            json
        }
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

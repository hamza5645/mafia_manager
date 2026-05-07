import Combine
import ConvexMobile
import Foundation

@MainActor
final class RealtimeService: ObservableObject {
    private let convex = ConvexService.shared

    @Published var isConnected = false
    @Published var isReconnecting = false
    @Published var connectionError: String?
    @Published var lastConnectTime: Date?
    @Published var reconnectAttempts = 0

    var onDisconnect: ((UUID) -> Void)?

    private var cancellables: [String: AnyCancellable] = [:]
    private var lastPlayersById: [UUID: SessionPlayer] = [:]
    private var lastActionsById: [UUID: GameAction] = [:]
    private var lastTentativeByKey: [String: TentativeSelection] = [:]

    func subscribeToSession(
        sessionId: UUID,
        viewerUserId: UUID?,
        onSessionUpdate: @escaping (GameSession) -> Void,
        onPlayerUpdate: @escaping (SessionPlayer) -> Void,
        onActionUpdate: @escaping (GameAction) -> Void,
        onTentativeSelection: @escaping (TentativeSelection) -> Void = { _ in },
        onDecodeError: @escaping (Error, String) -> Void = { _, _ in }
    ) async throws {
        await unsubscribeAll()

        let sessionKey = "session:\(sessionId.uuidString)"
        let sessionArgs: [String: ConvexEncodable?] = ["session_id": sessionId.uuidString.lowercased()]
        let playerArgs: [String: ConvexEncodable?] = [
            "session_id": sessionId.uuidString.lowercased(),
            "viewer_user_id": viewerUserId?.uuidString.lowercased(),
        ]

        cancellables["\(sessionKey):session"] = convex.subscribe(
            "sessions:getSessionById",
            with: sessionArgs,
            as: GameSession?.self
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                self?.handleCompletion(completion, sessionId: sessionId, table: "game_sessions", onDecodeError: onDecodeError)
            },
            receiveValue: { session in
                guard let session else { return }
                onSessionUpdate(session)
            }
        )

        cancellables["\(sessionKey):players"] = convex.subscribe(
            "sessions:getSessionPlayers",
            with: playerArgs,
            as: [SessionPlayer].self
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                self?.handleCompletion(completion, sessionId: sessionId, table: "session_players", onDecodeError: onDecodeError)
            },
            receiveValue: { [weak self] players in
                self?.handlePlayersSnapshot(players, onPlayerUpdate: onPlayerUpdate)
            }
        )

        cancellables["\(sessionKey):actions"] = convex.subscribe(
            "sessions:getAllActions",
            with: sessionArgs,
            as: [GameAction].self
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                self?.handleCompletion(completion, sessionId: sessionId, table: "game_actions", onDecodeError: onDecodeError)
            },
            receiveValue: { [weak self] actions in
                self?.handleActionsSnapshot(actions, onActionUpdate: onActionUpdate)
            }
        )

        cancellables["\(sessionKey):tentative"] = convex.subscribe(
            "sessions:listTentativeSelectionsForSession",
            with: sessionArgs,
            as: [TentativeSelection].self
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                self?.handleCompletion(completion, sessionId: sessionId, table: "tentative_selections", onDecodeError: onDecodeError)
            },
            receiveValue: { [weak self] selections in
                self?.handleTentativeSnapshot(selections, onTentativeSelection: onTentativeSelection)
            }
        )

        isConnected = true
        lastConnectTime = Date()
        reconnectAttempts = 0
    }

    func broadcastMessage(
        sessionId: UUID,
        event: String,
        payload: TentativeSelection
    ) async throws {
        guard event == "tentative_selection" else {
            return
        }

        try await convex.mutation(
            "sessions:setTentativeSelection",
            with: [
                "session_id": sessionId.uuidString.lowercased(),
                "actor_player_id": payload.actorPlayerId.uuidString.lowercased(),
                "target_player_id": payload.targetPlayerId?.uuidString.lowercased(),
                "action_type": payload.actionType.rawValue,
                "phase_index": Double(payload.phaseIndex),
            ]
        )
    }

    func unsubscribe(channelName: String) async {
        let matchingKeys = cancellables.keys.filter { $0.hasPrefix(channelName) }
        for key in matchingKeys {
            cancellables[key]?.cancel()
            cancellables.removeValue(forKey: key)
        }
        isConnected = !cancellables.isEmpty
    }

    func unsubscribeAll() async {
        cancellables.values.forEach { $0.cancel() }
        cancellables.removeAll()
        lastPlayersById.removeAll()
        lastActionsById.removeAll()
        lastTentativeByKey.removeAll()
        isConnected = false
    }

    func attemptResubscribe(
        sessionId: UUID,
        viewerUserId: UUID?,
        onSessionUpdate: @escaping (GameSession) -> Void,
        onPlayerUpdate: @escaping (SessionPlayer) -> Void,
        onActionUpdate: @escaping (GameAction) -> Void,
        onDecodeError: @escaping (Error, String) -> Void = { _, _ in },
        onReconnected: @escaping () async -> Void = {}
    ) {
        isReconnecting = true
        reconnectAttempts += 1
        Task { @MainActor in
            do {
                try await subscribeToSession(
                    sessionId: sessionId,
                    viewerUserId: viewerUserId,
                    onSessionUpdate: onSessionUpdate,
                    onPlayerUpdate: onPlayerUpdate,
                    onActionUpdate: onActionUpdate,
                    onDecodeError: onDecodeError
                )
                isReconnecting = false
                await onReconnected()
            } catch {
                isReconnecting = false
                connectionError = error.localizedDescription
                onDecodeError(error, "convex")
            }
        }
    }

    func forceReconnect(
        sessionId: UUID,
        viewerUserId: UUID?,
        onSessionUpdate: @escaping (GameSession) -> Void,
        onPlayerUpdate: @escaping (SessionPlayer) -> Void,
        onActionUpdate: @escaping (GameAction) -> Void,
        onTentativeSelection: @escaping (TentativeSelection) -> Void = { _ in },
        onDecodeError: @escaping (Error, String) -> Void = { _, _ in },
        onReconnected: @escaping () async -> Void = {}
    ) async throws {
        try await subscribeToSession(
            sessionId: sessionId,
            viewerUserId: viewerUserId,
            onSessionUpdate: onSessionUpdate,
            onPlayerUpdate: onPlayerUpdate,
            onActionUpdate: onActionUpdate,
            onTentativeSelection: onTentativeSelection,
            onDecodeError: onDecodeError
        )
        await onReconnected()
    }

    private func handleCompletion(
        _ completion: Subscribers.Completion<ClientError>,
        sessionId: UUID,
        table: String,
        onDecodeError: @escaping (Error, String) -> Void
    ) {
        if case .failure(let error) = completion {
            isConnected = false
            connectionError = error.localizedDescription
            onDecodeError(error, table)
            onDisconnect?(sessionId)
        }
    }

    private func handlePlayersSnapshot(
        _ players: [SessionPlayer],
        onPlayerUpdate: @escaping (SessionPlayer) -> Void
    ) {
        let incoming = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
        for player in players {
            if let previous = lastPlayersById[player.id] {
                if !previous.displayPropertiesEqual(to: player)
                    || previous.isOnline != player.isOnline
                    || previous.lastHeartbeat != player.lastHeartbeat {
                    onPlayerUpdate(player)
                }
            } else {
                onPlayerUpdate(player)
            }
        }
        lastPlayersById = incoming
    }

    private func handleActionsSnapshot(
        _ actions: [GameAction],
        onActionUpdate: @escaping (GameAction) -> Void
    ) {
        let incoming = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
        for action in actions {
            if let previous = lastActionsById[action.id] {
                if previous.targetPlayerId != action.targetPlayerId
                    || previous.actionData?.inspectorResult != action.actionData?.inspectorResult {
                    onActionUpdate(action)
                }
            } else {
                onActionUpdate(action)
            }
        }
        lastActionsById = incoming
    }

    private func handleTentativeSnapshot(
        _ selections: [TentativeSelection],
        onTentativeSelection: @escaping (TentativeSelection) -> Void
    ) {
        var incoming: [String: TentativeSelection] = [:]
        for selection in selections {
            let key = "\(selection.phaseIndex):\(selection.actionType.rawValue):\(selection.actorPlayerId.uuidString)"
            incoming[key] = selection
            if lastTentativeByKey[key]?.targetPlayerId != selection.targetPlayerId {
                onTentativeSelection(selection)
            }
        }
        lastTentativeByKey = incoming
    }
}

enum RealtimeError: LocalizedError {
    case channelNotFound

    var errorDescription: String? {
        switch self {
        case .channelNotFound:
            return "Realtime channel not found"
        }
    }
}

import Foundation
import Supabase
import Realtime
import Combine

@MainActor
final class RealtimeService: ObservableObject {
    private let supabase = SupabaseService.shared.client
    private var channels: [String: RealtimeChannelV2] = [:]

    // CRITICAL: Store subscription tokens to prevent deallocation
    // Without this, callbacks are garbage collected immediately and never fire
    private var subscriptionTokens: [String: [RealtimeSubscription]] = [:]

    // Published state for connection status
    @Published var isConnected: Bool = false
    @Published var isReconnecting: Bool = false
    @Published var connectionError: String?
    @Published var lastConnectTime: Date?
    @Published var reconnectAttempts: Int = 0

    // Reconnect state
    private var reconnectTask: Task<Void, Never>?
    private var lastEventTime: [String: Date] = [:]
    private var eventMonitoringTimer: Timer?
    private var channelStatusTasks: [String: Task<Void, Never>] = [:]

    // Disconnect callback for triggering recovery from MultiplayerGameStore
    var onDisconnect: ((UUID) -> Void)?

    // Event processor for serial event handling (prevents race conditions)
    private var eventProcessor: RealtimeEventProcessor?
    
    // Custom decoder for Supabase dates
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with fractional seconds first
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }

            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }

            // Fallback: Try with fractional seconds but assume UTC if no timezone
            // Handles format: "2025-11-24T16:33:27.104" (missing Z or +00:00)
            let fallbackFormatter = DateFormatter()
            fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
            fallbackFormatter.timeZone = TimeZone(secondsFromGMT: 0) // Assume UTC
            fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")
            if let date = fallbackFormatter.date(from: dateString) {
                return date
            }

            // Final fallback: Try without fractional seconds and no timezone
            fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            if let date = fallbackFormatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
        }
        return decoder
    }()

    // MARK: - Channel Management

    /// Subscribe to session updates
    /// - Parameters:
    ///   - sessionId: The session to subscribe to
    ///   - onSessionUpdate: Called when session data changes
    ///   - onPlayerUpdate: Called when player data changes
    ///   - onActionUpdate: Called when game actions change
    ///   - onTentativeSelection: Called for vote preview broadcasts
    ///   - onDecodeError: Called when a Realtime event fails to decode (triggers resync)
    func subscribeToSession(
        sessionId: UUID,
        onSessionUpdate: @escaping (GameSession) -> Void,
        onPlayerUpdate: @escaping (SessionPlayer) -> Void,
        onActionUpdate: @escaping (GameAction) -> Void,
        onTentativeSelection: @escaping (TentativeSelection) -> Void = { _ in },
        onDecodeError: @escaping (Error, String) -> Void = { _, _ in }
    ) async throws {
        let channelName = "session:\(sessionId.uuidString.lowercased())"

        // Remove existing channel if any
        await unsubscribe(channelName: channelName)

        // Create new channel
        let channel = supabase.realtimeV2.channel(channelName)

        // Array to store subscription tokens (prevents garbage collection)
        var tokens: [RealtimeSubscription] = []

        // CRITICAL: Create serial event processor to guarantee FIFO ordering
        // Without this, events from different tables can execute out of order,
        // causing one client to see stale phase data while others progress.
        let processor = RealtimeEventProcessor { @MainActor event in
            switch event {
            case .sessionUpdate(let session):
                onSessionUpdate(session)
            case .playerUpdate(let player):
                onPlayerUpdate(player)
            case .playerDeletion:
                // Player deletions trigger a refresh in the store via decode error path
                // This ensures immediate reaction rather than waiting for polling
                onDecodeError(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Player deleted")), "session_players")
            case .actionUpdate(let action):
                onActionUpdate(action)
            case .tentativeSelection(let selection):
                onTentativeSelection(selection)
            case .decodeError(let errorDescription, let table):
                // Create a simple error from the description for the callback
                let error = NSError(domain: "RealtimeService", code: -1, userInfo: [NSLocalizedDescriptionKey: errorDescription])
                onDecodeError(error, table)
            }
        }
        self.eventProcessor = processor

        // Subscribe to game_sessions table changes
        let sessionToken = await channel
            .onPostgresChange(
                AnyAction.self,
                schema: "public",
                table: "game_sessions",
                filter: "id=eq.\(sessionId.uuidString.lowercased())"
            ) { [weak self] payload in
                guard let self = self else { return }
                Task {
                    switch payload {
                    case .insert(let action):
                        print("🟢 [RealtimeService] Session INSERT event received")
                        do {
                            let session = try action.decodeRecord(as: GameSession.self, decoder: self.decoder)
                            print("✅ [RealtimeService] Session decoded: phase=\(session.currentPhase)")
                            await processor.enqueue(.sessionUpdate(session))
                        } catch {
                            print("❌ [RealtimeService] Failed to decode session from INSERT: \(error)")
                            if let jsonData = try? JSONEncoder().encode(action.record) {
                                print("❌ [RealtimeService] Raw data: \(String(data: jsonData, encoding: .utf8) ?? "Unable to encode")")
                            }
                            await processor.enqueue(.decodeError(errorDescription: error.localizedDescription, table: "game_sessions"))
                        }
                    case .update(let action):
                        print("🟡 [RealtimeService] Session UPDATE event received")
                        do {
                            let session = try action.decodeRecord(as: GameSession.self, decoder: self.decoder)
                            print("✅ [RealtimeService] Session decoded: phase=\(session.currentPhase), phaseData=\(String(describing: session.currentPhaseData))")
                            await processor.enqueue(.sessionUpdate(session))
                        } catch {
                            print("❌ [RealtimeService] Failed to decode session from UPDATE: \(error)")
                            if let jsonData = try? JSONEncoder().encode(action.record) {
                                print("❌ [RealtimeService] Raw data: \(String(data: jsonData, encoding: .utf8) ?? "Unable to encode")")
                            }
                            await processor.enqueue(.decodeError(errorDescription: error.localizedDescription, table: "game_sessions"))
                        }
                    case .delete:
                        print("🔴 [RealtimeService] Session DELETE event received")
                        // Session deleted - handle cleanup
                        break
                    }
                }
            }
        tokens.append(sessionToken)

        // Subscribe to session_players table changes
        let playerToken = await channel
            .onPostgresChange(
                AnyAction.self,
                schema: "public",
                table: "session_players",
                filter: "session_id=eq.\(sessionId.uuidString.lowercased())"
            ) { [weak self] payload in
                guard let self = self else { return }
                Task {
                    switch payload {
                    case .insert(let action):
                        print("🟢 [RealtimeService] Player INSERT event received")
                        do {
                            let player = try action.decodeRecord(as: SessionPlayer.self, decoder: self.decoder)
                            print("✅ [RealtimeService] Player decoded successfully: \(player.playerName) (ID: \(player.id))")
                            await processor.enqueue(.playerUpdate(player))
                        } catch {
                            print("❌ [RealtimeService] Failed to decode player from INSERT: \(error)")
                            if let jsonData = try? JSONEncoder().encode(action.record) {
                                print("❌ [RealtimeService] Raw data: \(String(data: jsonData, encoding: .utf8) ?? "Unable to encode")")
                            }
                            await processor.enqueue(.decodeError(errorDescription: error.localizedDescription, table: "session_players"))
                        }
                    case .update(let action):
                        print("🟡 [RealtimeService] Player UPDATE event received")
                        do {
                            let player = try action.decodeRecord(as: SessionPlayer.self, decoder: self.decoder)
                            print("✅ [RealtimeService] Player updated: \(player.playerName) (ID: \(player.id))")
                            await processor.enqueue(.playerUpdate(player))
                        } catch {
                            print("❌ [RealtimeService] Failed to decode player from UPDATE: \(error)")
                            await processor.enqueue(.decodeError(errorDescription: error.localizedDescription, table: "session_players"))
                        }
                    case .delete:
                        print("🔴 [RealtimeService] Player DELETE event received")
                        // For deletions, trigger a player refresh via decode error path
                        // This ensures we get the current state from the server
                        print("✅ [RealtimeService] Player deletion detected - triggering refresh")
                        await processor.enqueue(.playerDeletion(deletedPlayerId: nil))
                    }
                }
            }
        tokens.append(playerToken)

        // Subscribe to game_actions table changes
        let actionToken = await channel
            .onPostgresChange(
                AnyAction.self,
                schema: "public",
                table: "game_actions",
                filter: "session_id=eq.\(sessionId.uuidString.lowercased())"
            ) { [weak self] payload in
                guard let self = self else { return }
                Task {
                    switch payload {
                    case .insert(let action):
                        do {
                            let gameAction = try action.decodeRecord(as: GameAction.self, decoder: self.decoder)
                            await processor.enqueue(.actionUpdate(gameAction))
                        } catch {
                            print("❌ [RealtimeService] Failed to decode action from INSERT: \(error)")
                            await processor.enqueue(.decodeError(errorDescription: error.localizedDescription, table: "game_actions"))
                        }
                    case .update(let action):
                        do {
                            let gameAction = try action.decodeRecord(as: GameAction.self, decoder: self.decoder)
                            await processor.enqueue(.actionUpdate(gameAction))
                        } catch {
                            print("❌ [RealtimeService] Failed to decode action from UPDATE: \(error)")
                            await processor.enqueue(.decodeError(errorDescription: error.localizedDescription, table: "game_actions"))
                        }
                    case .delete:
                        break
                    }
                }
            }
        tokens.append(actionToken)

        // Subscribe to tentative selection broadcasts (real-time vote preview)
        let tentativeToken = await channel.onBroadcast(event: "tentative_selection") { [weak self] message in
            guard let self = self else { return }
            Task {
                do {
                    // The message is a [String: AnyJSON] dictionary from Supabase
                    // AnyJSON is Codable, so we encode it to Data, then decode as TentativeSelection

                    // Check if payload is nested (Supabase may wrap broadcast payloads)
                    let payloadToEncode: JSONObject
                    if let innerPayload = message["payload"], case .object(let inner) = innerPayload {
                        payloadToEncode = inner
                    } else {
                        // Message is the payload directly
                        payloadToEncode = message
                    }

                    // Encode the AnyJSON dictionary to Data using JSONEncoder
                    let encoder = JSONEncoder()
                    let jsonData = try encoder.encode(payloadToEncode)

                    // Decode using our custom decoder with date handling
                    let selection = try self.decoder.decode(TentativeSelection.self, from: jsonData)
                    print("📡 [RealtimeService] Tentative selection received: \(selection.actionType) -> \(selection.targetPlayerId?.uuidString.prefix(8) ?? "nil")")
                    await processor.enqueue(.tentativeSelection(selection))
                } catch {
                    print("❌ [RealtimeService] Failed to decode tentative selection: \(error)")
                    // Log the raw message keys for debugging
                    print("❌ [RealtimeService] Raw message keys: \(message.keys)")
                    // Don't trigger resync for tentative selections - they're not critical
                }
            }
        }
        tokens.append(tentativeToken)

        // CRITICAL: Allow Supabase's filter registrations (scheduled via Task { @MainActor … })
        // to run before we join the channel; otherwise no postgres filters are sent to server.
        // Without this yield, subscribeWithError() joins immediately with zero filters configured.
        await Task.yield()

        // Subscribe to the channel
        do {
            try await channel.subscribeWithError()

            // Store channel reference AND subscription tokens
            channels[channelName] = channel
            subscriptionTokens[channelName] = tokens
            isConnected = true
            lastConnectTime = Date()
            connectionError = nil
            reconnectAttempts = 0
            isReconnecting = false

            print("✅ [RealtimeService] Connected to channel: \(channelName) with \(tokens.count) subscriptions")

            // Start monitoring channel status for disconnection detection
            startChannelStatusMonitoring(channelName: channelName, sessionId: sessionId, channel: channel)
        } catch {
            print("❌ [RealtimeService] Failed to subscribe to channel \(channelName): \(error)")
            connectionError = error.localizedDescription
            isConnected = false
            throw error
        }
    }

    /// Subscribe to presence (player online/offline status)
    func subscribeToPresence(
        sessionId: UUID,
        myPlayerId: UUID,
        onPresenceSync: @escaping ([UUID: PresenceState]) -> Void
    ) async throws {
        let channelName = "presence:\(sessionId.uuidString.lowercased())"

        // Remove existing channel if any
        await unsubscribe(channelName: channelName)

        // Create presence channel
        let channel = supabase.realtimeV2.channel(channelName)

        // Track my presence
        let presenceState = PresenceState(playerId: myPlayerId, lastSeen: Date())
        try await channel.track(presenceState)

        // Array to store subscription tokens (prevents garbage collection)
        var tokens: [RealtimeSubscription] = []

        // Listen to presence changes
        let presenceToken = await channel.onPresenceChange { payload in
            Task { @MainActor in
                // Convert presence payload to dictionary
                var presenceMap: [UUID: PresenceState] = [:]

                // Parse joins
                for (key, _) in payload.joins {
                    if let playerId = UUID(uuidString: key) {
                        presenceMap[playerId] = PresenceState(playerId: playerId, lastSeen: Date())
                    }
                }

                // Parse leaves
                for (key, _) in payload.leaves {
                    if let playerId = UUID(uuidString: key) {
                        presenceMap[playerId] = nil
                    }
                }

                onPresenceSync(presenceMap)
            }
        }
        tokens.append(presenceToken)

        // CRITICAL: Allow Supabase's presence registration (scheduled via Task { @MainActor … })
        // to run before we join the channel.
        await Task.yield()

        // Subscribe
        do {
            try await channel.subscribeWithError()

            // Store channel reference AND subscription tokens
            channels[channelName] = channel
            subscriptionTokens[channelName] = tokens
            isConnected = true
            lastConnectTime = Date()
            connectionError = nil
            reconnectAttempts = 0
            isReconnecting = false

            print("✅ [RealtimeService] Connected to presence channel: \(channelName) with \(tokens.count) subscriptions")
        } catch {
            print("❌ [RealtimeService] Failed to subscribe to presence channel \(channelName): \(error)")
            connectionError = error.localizedDescription
            isConnected = false
            throw error
        }
    }

    /// Unsubscribe from a channel
    func unsubscribe(channelName: String) async {
        // Cancel channel status monitoring task
        channelStatusTasks[channelName]?.cancel()
        channelStatusTasks.removeValue(forKey: channelName)

        // Cancel all subscription tokens for this channel
        if let tokens = subscriptionTokens[channelName] {
            print("🔴 [RealtimeService] Cancelling \(tokens.count) subscription(s) for channel: \(channelName)")
            tokens.forEach { $0.cancel() }
            subscriptionTokens.removeValue(forKey: channelName)
        }

        // Remove the channel
        if let channel = channels[channelName] {
            await supabase.realtimeV2.removeChannel(channel)
            channels.removeValue(forKey: channelName)
        }
    }

    /// Unsubscribe from all channels
    func unsubscribeAll() async {
        // CRITICAL: Cancel reconnect task FIRST to prevent race condition
        // Without this, a reconnect loop can re-subscribe AFTER we've cleaned up
        reconnectTask?.cancel()
        reconnectTask = nil
        isReconnecting = false
        reconnectAttempts = 0

        // Allow cancellation to propagate before cleanup
        await Task.yield()

        // Cancel all channel status monitoring tasks
        channelStatusTasks.values.forEach { $0.cancel() }
        channelStatusTasks.removeAll()

        // Cancel all subscription tokens
        for (channelName, tokens) in subscriptionTokens {
            print("🔴 [RealtimeService] Cancelling \(tokens.count) subscription(s) for channel: \(channelName)")
            tokens.forEach { $0.cancel() }
        }
        subscriptionTokens.removeAll()

        // Remove all channels
        for (_, channel) in channels {
            await supabase.realtimeV2.removeChannel(channel)
        }
        channels.removeAll()
        isConnected = false
    }

    /// Send a broadcast message to all players in a session
    func broadcastMessage<T: Codable>(
        sessionId: UUID,
        event: String,
        payload: T
    ) async throws {
        let channelName = "session:\(sessionId.uuidString.lowercased())"

        guard let channel = channels[channelName] else {
            throw RealtimeError.channelNotFound
        }

        try await channel.broadcast(event: event, message: payload)
    }

    // MARK: - Connection Monitoring

    /// Trigger a snapshot resync when reconnecting
    func triggerSnapshotResync(callback: @escaping () async -> Void) {
        Task {
            print("🔄 [RealtimeService] Triggering snapshot resync after reconnect")
            await callback()
        }
    }

    /// Attempt to resubscribe with exponential backoff
    /// - Parameters:
    ///   - sessionId: The session ID to resubscribe to
    ///   - onSessionUpdate: Callback for session updates
    ///   - onPlayerUpdate: Callback for player updates
    ///   - onActionUpdate: Callback for action updates
    ///   - onDecodeError: Callback for decode errors (triggers resync)
    ///   - onReconnected: Called when successfully reconnected
    /// PERF: Refactored from recursive to loop-based to prevent call stack growth
    func attemptResubscribe(
        sessionId: UUID,
        onSessionUpdate: @escaping (GameSession) -> Void,
        onPlayerUpdate: @escaping (SessionPlayer) -> Void,
        onActionUpdate: @escaping (GameAction) -> Void,
        onDecodeError: @escaping (Error, String) -> Void = { _, _ in },
        onReconnected: @escaping () async -> Void
    ) {
        // Cancel any pending reconnect task
        reconnectTask?.cancel()

        reconnectTask = Task {
            isReconnecting = true

            // Exponential backoff constants
            let baseDelay: Double = 1.0
            let maxDelay: Double = 30.0
            let maxAttempts = 10

            // Loop-based retry instead of recursion
            while reconnectAttempts < maxAttempts && !Task.isCancelled {
                let delay = min(baseDelay * pow(2.0, Double(reconnectAttempts)), maxDelay)
                print("⏳ [RealtimeService] Attempting reconnect in \(delay)s (attempt \(reconnectAttempts + 1)/\(maxAttempts))")

                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                guard !Task.isCancelled else {
                    print("🛑 [RealtimeService] Reconnect attempt cancelled")
                    break
                }

                do {
                    try await subscribeToSession(
                        sessionId: sessionId,
                        onSessionUpdate: onSessionUpdate,
                        onPlayerUpdate: onPlayerUpdate,
                        onActionUpdate: onActionUpdate,
                        onDecodeError: onDecodeError
                    )

                    // Successfully reconnected
                    print("✅ [RealtimeService] Reconnected successfully after \(reconnectAttempts + 1) attempts")
                    isReconnecting = false

                    // Trigger snapshot resync
                    await onReconnected()
                    return // Success - exit the loop and task
                } catch {
                    reconnectAttempts += 1
                    print("🔄 [RealtimeService] Reconnect attempt \(reconnectAttempts) failed, will retry")
                }
            }

            // Max attempts reached or cancelled
            if reconnectAttempts >= maxAttempts {
                print("❌ [RealtimeService] Max reconnect attempts reached. Giving up.")
                connectionError = "Failed to reconnect after \(maxAttempts) attempts"
            }
            isReconnecting = false
        }
    }

    /// Force reconnect after app resume - don't trust existing connection state
    /// This is called when the app returns from background to ensure fresh connections
    func forceReconnect(
        sessionId: UUID,
        onSessionUpdate: @escaping (GameSession) -> Void,
        onPlayerUpdate: @escaping (SessionPlayer) -> Void,
        onActionUpdate: @escaping (GameAction) -> Void,
        onTentativeSelection: @escaping (TentativeSelection) -> Void = { _ in },
        onDecodeError: @escaping (Error, String) -> Void = { _, _ in },
        onReconnected: @escaping () async -> Void
    ) async {
        print("🔄 [RealtimeService] Force reconnect initiated for session: \(sessionId)")

        // 1. Cancel any pending reconnect attempts
        reconnectTask?.cancel()
        reconnectTask = nil

        // 2. Unsubscribe from all channels (cleanup potentially stale connections)
        await unsubscribeAll()

        // 3. Reset connection state
        isConnected = false
        reconnectAttempts = 0
        connectionError = nil
        isReconnecting = false

        // 4. Attempt fresh subscription
        do {
            try await subscribeToSession(
                sessionId: sessionId,
                onSessionUpdate: onSessionUpdate,
                onPlayerUpdate: onPlayerUpdate,
                onActionUpdate: onActionUpdate,
                onTentativeSelection: onTentativeSelection,
                onDecodeError: onDecodeError
            )

            print("✅ [RealtimeService] Force reconnect successful")
            await onReconnected()
        } catch {
            print("❌ [RealtimeService] Force reconnect failed: \(error)")
            connectionError = error.localizedDescription

            // Fall back to exponential backoff retry
            attemptResubscribe(
                sessionId: sessionId,
                onSessionUpdate: onSessionUpdate,
                onPlayerUpdate: onPlayerUpdate,
                onActionUpdate: onActionUpdate,
                onDecodeError: onDecodeError,
                onReconnected: onReconnected
            )
        }
    }

    /// Schedule cleanup of reconnect resources on the main thread
    func scheduleCleanup() {
        Task { @MainActor [weak self] in
            self?.reconnectTask?.cancel()
            self?.reconnectTask = nil
            self?.eventMonitoringTimer?.invalidate()
            self?.eventMonitoringTimer = nil
            // Cancel all channel status monitoring tasks
            self?.channelStatusTasks.values.forEach { $0.cancel() }
            self?.channelStatusTasks.removeAll()
        }
    }

    // MARK: - Channel Status Monitoring

    /// Start monitoring channel status to detect disconnections
    /// Uses Supabase channel status async sequence to detect when channel is no longer subscribed
    private func startChannelStatusMonitoring(channelName: String, sessionId: UUID, channel: RealtimeChannelV2) {
        // Cancel any existing monitoring task for this channel
        channelStatusTasks[channelName]?.cancel()

        let monitoringTask = Task { [weak self] in
            // Monitor using channel.status async sequence
            for await status in channel.statusChange {
                guard !Task.isCancelled else { break }

                await MainActor.run {
                    switch status {
                    case .subscribed:
                        print("✅ [RealtimeService] Channel \(channelName) is subscribed")
                        self?.isConnected = true
                    case .unsubscribed:
                        print("⚠️ [RealtimeService] Channel \(channelName) unsubscribed - triggering recovery")
                        self?.handleDisconnection(sessionId: sessionId, channelName: channelName)
                    case .subscribing:
                        print("🔄 [RealtimeService] Channel \(channelName) is subscribing...")
                    case .unsubscribing:
                        print("🔄 [RealtimeService] Channel \(channelName) is unsubscribing...")
                    }
                }
            }
        }

        channelStatusTasks[channelName] = monitoringTask
    }

    /// Handle disconnection by updating state and notifying MultiplayerGameStore
    private func handleDisconnection(sessionId: UUID, channelName: String) {
        // Only trigger recovery if we think we should still be connected
        guard channels[channelName] != nil else { return }

        print("🔴 [RealtimeService] Disconnection detected for session: \(sessionId)")
        isConnected = false
        connectionError = "Connection lost"

        // Notify MultiplayerGameStore to trigger recovery
        onDisconnect?(sessionId)
    }
}

// MARK: - Presence State

struct PresenceState: Codable {
    let playerId: UUID
    let lastSeen: Date

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case lastSeen = "last_seen"
    }
}

// MARK: - Errors

enum RealtimeError: LocalizedError {
    case channelNotFound
    case subscriptionFailed
    case broadcastFailed

    var errorDescription: String? {
        switch self {
        case .channelNotFound:
            return "Realtime channel not found"
        case .subscriptionFailed:
            return "Failed to subscribe to realtime updates"
        case .broadcastFailed:
            return "Failed to broadcast message"
        }
    }
}

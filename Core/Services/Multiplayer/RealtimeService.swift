import Foundation
import Supabase
import Realtime
import Combine

@MainActor
final class RealtimeService: ObservableObject {
    private let supabase = SupabaseService.shared.client
    private var channels: [String: RealtimeChannelV2] = [:]

    // Published state for connection status
    @Published var isConnected: Bool = false
    @Published var connectionError: String?
    
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
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
        }
        return decoder
    }()

    // MARK: - Channel Management

    /// Subscribe to session updates
    func subscribeToSession(
        sessionId: UUID,
        onSessionUpdate: @escaping (GameSession) -> Void,
        onPlayerUpdate: @escaping (SessionPlayer) -> Void,
        onActionUpdate: @escaping (GameAction) -> Void
    ) async throws {
        let channelName = "session:\(sessionId.uuidString)"

        // Remove existing channel if any
        await unsubscribe(channelName: channelName)

        // Create new channel
        let channel = supabase.realtimeV2.channel(channelName)

        // Subscribe to game_sessions table changes
        await channel
            .onPostgresChange(
                AnyAction.self,
                schema: "public",
                table: "game_sessions",
                filter: "id=eq.\(sessionId.uuidString)"
            ) { payload in
                Task { @MainActor in
                    switch payload {
                    case .insert(let action):
                        print("🟢 [RealtimeService] Session INSERT event received")
                        do {
                            let session = try action.decodeRecord(as: GameSession.self, decoder: self.decoder)
                            print("✅ [RealtimeService] Session decoded: phase=\(session.currentPhase)")
                            onSessionUpdate(session)
                        } catch {
                            print("❌ [RealtimeService] Failed to decode session from INSERT: \(error)")
                            if let jsonData = try? JSONEncoder().encode(action.record) {
                                print("❌ [RealtimeService] Raw data: \(String(data: jsonData, encoding: .utf8) ?? "Unable to encode")")
                            }
                        }
                    case .update(let action):
                        print("🟡 [RealtimeService] Session UPDATE event received")
                        do {
                            let session = try action.decodeRecord(as: GameSession.self, decoder: self.decoder)
                            print("✅ [RealtimeService] Session decoded: phase=\(session.currentPhase), phaseData=\(String(describing: session.currentPhaseData))")
                            onSessionUpdate(session)
                        } catch {
                            print("❌ [RealtimeService] Failed to decode session from UPDATE: \(error)")
                            if let jsonData = try? JSONEncoder().encode(action.record) {
                                print("❌ [RealtimeService] Raw data: \(String(data: jsonData, encoding: .utf8) ?? "Unable to encode")")
                            }
                        }
                    case .delete:
                        print("🔴 [RealtimeService] Session DELETE event received")
                        // Session deleted - handle cleanup
                        break
                    }
                }
            }

        // Subscribe to session_players table changes
        await channel
            .onPostgresChange(
                AnyAction.self,
                schema: "public",
                table: "session_players",
                filter: "session_id=eq.\(sessionId.uuidString)"
            ) { payload in
                Task { @MainActor in
                    switch payload {
                    case .insert(let action):
                        print("🟢 [RealtimeService] Player INSERT event received")
                        do {
                            let player = try action.decodeRecord(as: SessionPlayer.self, decoder: self.decoder)
                            print("✅ [RealtimeService] Player decoded successfully: \(player.playerName) (ID: \(player.id))")
                            onPlayerUpdate(player)
                        } catch {
                            print("❌ [RealtimeService] Failed to decode player from INSERT: \(error)")
                            if let jsonData = try? JSONEncoder().encode(action.record) {
                                print("❌ [RealtimeService] Raw data: \(String(data: jsonData, encoding: .utf8) ?? "Unable to encode")")
                            }
                        }
                    case .update(let action):
                        print("🟡 [RealtimeService] Player UPDATE event received")
                        do {
                            let player = try action.decodeRecord(as: SessionPlayer.self, decoder: self.decoder)
                            print("✅ [RealtimeService] Player updated: \(player.playerName) (ID: \(player.id))")
                            onPlayerUpdate(player)
                        } catch {
                            print("❌ [RealtimeService] Failed to decode player from UPDATE: \(error)")
                        }
                    case .delete(let action):
                        print("🔴 [RealtimeService] Player DELETE event received")
                        // For deletions, we can't decode a full player object
                        // The store will handle this by refreshing the players list
                        // This ensures we get the current state from the server
                        print("✅ [RealtimeService] Player deletion detected - refresh will be handled by store")
                    }
                }
            }

        // Subscribe to game_actions table changes
        await channel
            .onPostgresChange(
                AnyAction.self,
                schema: "public",
                table: "game_actions",
                filter: "session_id=eq.\(sessionId.uuidString)"
            ) { payload in
                Task { @MainActor in
                    switch payload {
                    case .insert(let action):
                        do {
                            let gameAction = try action.decodeRecord(as: GameAction.self, decoder: self.decoder)
                            onActionUpdate(gameAction)
                        } catch {
                            print("❌ [RealtimeService] Failed to decode action from INSERT: \(error)")
                        }
                    case .update(let action):
                        do {
                            let gameAction = try action.decodeRecord(as: GameAction.self, decoder: self.decoder)
                            onActionUpdate(gameAction)
                        } catch {
                            print("❌ [RealtimeService] Failed to decode action from UPDATE: \(error)")
                        }
                    case .delete:
                        break
                    }
                }
            }

        // Subscribe to the channel
        try await channel.subscribeWithError()

        // Store channel reference
        channels[channelName] = channel
        isConnected = true
    }

    /// Subscribe to presence (player online/offline status)
    func subscribeToPresence(
        sessionId: UUID,
        myPlayerId: UUID,
        onPresenceSync: @escaping ([UUID: PresenceState]) -> Void
    ) async throws {
        let channelName = "presence:\(sessionId.uuidString)"

        // Remove existing channel if any
        await unsubscribe(channelName: channelName)

        // Create presence channel
        let channel = supabase.realtimeV2.channel(channelName)

        // Track my presence
        let presenceState = PresenceState(playerId: myPlayerId, lastSeen: Date())
        try await channel.track(presenceState)

        // Listen to presence changes
        await channel.onPresenceChange { payload in
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

        // Subscribe
        try await channel.subscribeWithError()

        // Store channel reference
        channels[channelName] = channel
    }

    /// Unsubscribe from a channel
    func unsubscribe(channelName: String) async {
        if let channel = channels[channelName] {
            await supabase.realtimeV2.removeChannel(channel)
            channels.removeValue(forKey: channelName)
        }
    }

    /// Unsubscribe from all channels
    func unsubscribeAll() async {
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
        let channelName = "session:\(sessionId.uuidString)"

        guard let channel = channels[channelName] else {
            throw RealtimeError.channelNotFound
        }

        try await channel.broadcast(event: event, message: payload)
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

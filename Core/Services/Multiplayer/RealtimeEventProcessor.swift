import Foundation

/// Event types that can be processed by the RealtimeEventProcessor
/// Made Sendable for safe cross-actor transport
enum RealtimeEvent: Sendable {
    case sessionUpdate(GameSession)
    case playerUpdate(SessionPlayer)
    case playerDeletion(deletedPlayerId: UUID?)
    case actionUpdate(GameAction)
    case tentativeSelection(TentativeSelection)
    case decodeError(errorDescription: String, table: String)
}

/// Serial actor that guarantees FIFO ordering of Realtime events
///
/// CRITICAL: Swift's `Task { @MainActor in }` does NOT guarantee FIFO ordering.
/// Events from different tables (game_sessions, session_players, game_actions)
/// can execute out of order, causing one client to see stale phase data while others progress.
///
/// This actor ensures all events are processed in the order they arrive,
/// preventing race conditions during phase transitions.
actor RealtimeEventProcessor {

    /// Callback handler type that runs on MainActor
    typealias EventHandler = @MainActor (RealtimeEvent) async -> Void

    private var pendingEvents: [RealtimeEvent] = []
    private var isProcessing = false
    private let handler: EventHandler

    /// Initialize with an event handler that will be called for each event
    /// - Parameter handler: The handler to process events (runs on MainActor)
    init(handler: @escaping EventHandler) {
        self.handler = handler
    }

    /// Enqueue an event for serial processing
    /// Events are processed in FIFO order, one at a time
    /// - Parameter event: The event to process
    func enqueue(_ event: RealtimeEvent) async {
        pendingEvents.append(event)

        // If already processing, the event will be picked up by the existing loop
        guard !isProcessing else { return }

        isProcessing = true
        // Use defer to ensure isProcessing is always reset, even if handler fails
        defer { isProcessing = false }

        while !pendingEvents.isEmpty {
            let nextEvent = pendingEvents.removeFirst()
            await handler(nextEvent)
        }
    }

    /// Get the current queue depth (for debugging)
    var queueDepth: Int {
        pendingEvents.count
    }

    /// Check if currently processing events
    var processing: Bool {
        isProcessing
    }
}

import Combine
import ConvexMobile
import Foundation

/// Subscriptions, heartbeat and host-offline handling (api_contract 4, §8.1.4, §8.3, §8.4).
extension MultiplayerGameStore {
    static let hostOfflineThreshold: TimeInterval = 15

    func setAuthStore(_ authStore: AuthStore) {
        self.authStore = authStore
        // A new identity means a different guest proof in the subscription arguments.
        identityObserver = authStore.$identityRevision
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.subscriptions.forEach { $0.start() } }
    }

    func startSubscriptions(sessionId: UUID) {
        let convex = ConvexService.shared
        let args: [String: ConvexEncodable?] = ["session_id": sessionId.uuidString.lowercased()]
        subscriptions = [
            SubscriptionSupervisor(
                { convex.subscribe("views:getSessionView", with: args, as: SessionView?.self) },
                onValue: { [weak self] in self?.apply(sessionView: $0) }
            ),
            SubscriptionSupervisor(
                { convex.subscribe("views:getPlayers", with: args, as: [SessionPlayer].self) },
                onValue: { [weak self] in self?.apply(players: $0) }
            ),
            SubscriptionSupervisor(
                { convex.subscribe("views:getRoundState", with: args, as: RoundState?.self) },
                onValue: { [weak self] in self?.apply(roundState: $0) }
            ),
        ]
        for subscription in subscriptions {
            subscription.onStatusChange = { [weak self] in self?.updateConnectionStatus() }
            subscription.start()
        }
    }

    /// The user's Retry: restart failed or waiting subscriptions and re-check who I am.
    func retryConnection() {
        subscriptions.forEach { $0.restartIfNeeded() }
        if needsSignIn { recoverIdentity() }
    }

    func updateConnectionStatus() {
        var live = !subscriptions.isEmpty
        var banner = false
        var failure: String?
        for subscription in subscriptions {
            switch subscription.status {
            case .live:
                continue
            case .retrying(let attempt):
                banner = banner || attempt >= 3
            case .failed(let message):
                failure = failure ?? message
            case .idle, .connecting:
                break
            }
            live = false
        }
        isRealtimeConnected = live
        showsReconnectBanner = banner
        connectionError = failure
    }

    // MARK: - App lifecycle

    func handleAppResume() async {
        isInBackground = false
        guard sessionId != nil else { return }
        await authStore?.ensureValidSession()
        guard !isInBackground else { return }
        subscriptions.forEach { $0.restartIfNeeded() }
        startTicking() // Sends a heartbeat immediately.
    }

    func prepareForBackground() {
        isInBackground = true
        tickTask?.cancel()
        tickTask = nil
    }

    // MARK: - Heartbeat and host monitor

    /// Every 5 s: heartbeat my seat, then check the host's heartbeat locally.
    func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled, let self {
                await self.tick()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func tick() async {
        guard let sessionId else { return }
        do {
            try await sessionService.heartbeat(sessionId: sessionId)
        } catch {
            print("⚠️ [MultiplayerGameStore] Heartbeat failed: \(error.localizedDescription)")
        }
        await checkHost()
    }

    /// No network read: the server enforces staleness again in `sessions:claimHost`.
    func checkHost() async {
        guard !isHost, let sessionId, let session = currentSession,
              let host = players.first(where: { $0.userId == session.hostUserId && !$0.isBot }) else {
            isHostOffline = false
            return
        }
        let now = Date()
        isHostOffline = now.timeIntervalSince(host.lastHeartbeat) > Self.hostOfflineThreshold
        guard isHostOffline,
              Self.nextHost(in: players, excluding: session.hostUserId, now: now)?.isMe == true else { return }
        do {
            try await sessionService.claimHost(sessionId: sessionId)
        } catch {
            // HOST_ACTIVE / HOST_SUCCESSOR are expected races; the next tick tries again.
            print("⚠️ [MultiplayerGameStore] Host claim failed: \(error.localizedDescription)")
        }
    }

    /// The earliest-joined living human with a fresh heartbeat (server `nextHostAfterDeath`).
    static func nextHost(in players: [SessionPlayer], excluding hostUserId: UUID, now: Date) -> SessionPlayer? {
        players
            .filter {
                $0.isAlive && !$0.isBot && $0.userId != nil && $0.userId != hostUserId
                    && now.timeIntervalSince($0.lastHeartbeat) <= hostOfflineThreshold
            }
            .min { $0.joinedAt < $1.joinedAt }
    }
}

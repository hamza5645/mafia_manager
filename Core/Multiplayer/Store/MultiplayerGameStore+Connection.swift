import Combine
import ConvexMobile
import Foundation
import UIKit

/// Subscriptions, heartbeat and host-offline handling (api_contract 5, §8.1.4, §8.3, §8.4).
extension MultiplayerGameStore {
    static let tickInterval: Duration = .seconds(5)
    /// How long the socket may reconnect before the banner shows.
    static let slowConnectionDelay: Duration = .milliseconds(2_500)
    /// How long a user's mutation may wait before the banner shows.
    static let slowMutationDelay: Duration = .seconds(5)

    func setAuthStore(_ authStore: AuthStore) {
        self.authStore = authStore
        // The subscription arguments depend on the guest proof only; an account switch
        // re-authenticates the socket, which re-runs every query by itself.
        identityObserver = authStore.$identityRevision
            .map { [weak authStore] _ in authStore?.activeGuestProof }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.subscriptions.forEach { $0.start() } }
    }

    func startSubscriptions(sessionId: UUID) {
        let service = sessionService
        subscriptions = [
            SubscriptionSupervisor(
                { service.watch("views:getSessionView", sessionId: sessionId, as: SessionView?.self) },
                label: "getSessionView", sleep: sleep,
                onValue: { [weak self] in self?.apply(sessionView: $0) }
            ),
            SubscriptionSupervisor(
                { service.watch("views:getPlayers", sessionId: sessionId, as: [SessionPlayer].self) },
                label: "getPlayers", sleep: sleep,
                onValue: { [weak self] in self?.apply(players: $0) }
            ),
            SubscriptionSupervisor(
                { service.watch("views:getRoundState", sessionId: sessionId, as: RoundState?.self) },
                label: "getRoundState", sleep: sleep,
                onValue: { [weak self] in self?.apply(roundState: $0) }
            ),
            SubscriptionSupervisor(
                { service.watch("views:getHostPresence", sessionId: sessionId, as: HostPresence?.self) },
                label: "getHostPresence", sleep: sleep,
                onValue: { [weak self] in self?.apply(hostPresence: $0) }
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

    /// "Reconnecting…" when a subscription keeps failing, the socket has been reconnecting
    /// for a while, or one of my taps has been sending for a while.
    func updateConnectionStatus() {
        var retrying = false
        var failure: String?
        for subscription in subscriptions {
            switch subscription.status {
            case .retrying(let attempt):
                retrying = retrying || attempt >= 3
            case .failed(let message):
                failure = failure ?? message
            case .idle, .connecting, .live:
                break
            }
        }
        let banner = sessionId != nil && (retrying || isConnectionSlow || !slowMutations.isEmpty)
        if showsReconnectBanner != banner { showsReconnectBanner = banner }
        if connectionError != failure { connectionError = failure }
    }

    func handleConnectionState(_ state: ConvexConnectionState) {
        slowConnectionTask?.cancel()
        let reconnected = isSocketConnecting && state != .connecting
        isSocketConnecting = state == .connecting
        if reconnected { restartHostPresenceClock() }
        if isSocketConnecting {
            slowConnectionTask = Task { [weak self, sleep] in
                await sleep(Self.slowConnectionDelay)
                guard !Task.isCancelled, let self, self.isSocketConnecting else { return }
                self.isConnectionSlow = true
                self.updateConnectionStatus()
            }
        } else {
            isConnectionSlow = false
        }
        refreshHostOffline()
        updateConnectionStatus()
    }

    /// Runs a user's mutation; past `slowMutationDelay` it shows the banner until it returns.
    @discardableResult
    func sending<T>(_ call: () async throws -> T) async throws -> T {
        let id = UUID()
        let timer = Task { [weak self, sleep] in
            await sleep(Self.slowMutationDelay)
            guard !Task.isCancelled, let self else { return }
            self.slowMutations.insert(id)
            self.updateConnectionStatus()
        }
        defer {
            timer.cancel()
            if slowMutations.remove(id) != nil { updateConnectionStatus() }
        }
        return try await call()
    }

    // MARK: - App lifecycle

    func handleAppResume() async {
        isInBackground = false
        guard sessionId != nil else { return }
        isReclaimPending = true
        restartHostPresenceClock()
        // Heartbeat right away so the room sees me before the token refresh finishes.
        startTicking()
        await authStore?.ensureValidSession()
        // The session can be cleared, or the app backgrounded again, during the refresh.
        guard sessionId != nil, !isInBackground else { return }
        subscriptions.forEach { $0.restartIfNeeded() }
    }

    func prepareForBackground() {
        isInBackground = true
        tickTask?.cancel()
        tickTask = nil
        guard let sessionId else { return }
        // One last heartbeat keeps me fresh for as long as possible while suspended.
        endFinalHeartbeat()
        finalHeartbeatTask = UIApplication.shared.beginBackgroundTask(withName: "Final heartbeat") { [weak self] in
            self?.endFinalHeartbeat()
        }
        let service = sessionService
        Task { [weak self] in
            try? await service.heartbeat(sessionId: sessionId)
            self?.endFinalHeartbeat()
        }
    }

    private func endFinalHeartbeat() {
        guard finalHeartbeatTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(finalHeartbeatTask)
        finalHeartbeatTask = .invalid
    }

    // MARK: - Heartbeat and host monitor

    /// Every 5 s: heartbeat my seat, check the host, and retry host automation
    /// (a failed bot submission or role-reveal advance) without waiting for a snapshot.
    func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self, sleep] in
            while !Task.isCancelled, self != nil {
                self?.tick()
                await sleep(Self.tickInterval)
            }
        }
    }

    private func tick() {
        guard let sessionId else { return }
        sendHeartbeat(sessionId: sessionId)
        checkHost()
        runHostAutomation()
    }

    /// One heartbeat at a time, which the tick does not wait for. During an outage one heartbeat
    /// waits in the Convex client until its time limit instead of one per tick (each queued one
    /// is replayed on reconnect); the limit lets the next one go if a call never returns.
    private func sendHeartbeat(sessionId: UUID) {
        guard heartbeatInFlight != sessionId else { return }
        heartbeatInFlight = sessionId
        Task { [weak self, sessionService] in
            var sent = false
            do {
                try await sessionService.heartbeat(sessionId: sessionId)
                sent = true
            } catch {
                print("⚠️ [MultiplayerGameStore] Heartbeat failed: \(error.localizedDescription)")
            }
            guard let self else { return }
            if heartbeatInFlight == sessionId { heartbeatInFlight = nil }
            guard sent, self.sessionId == sessionId, isReclaimPending else { return }
            isReclaimPending = false
            await reclaimLobbyIfNeeded()
        }
    }

    /// Back from the background: an original host who lost the lobby while away takes it back.
    private func reclaimLobbyIfNeeded() async {
        guard let sessionId, let view = sessionView, view.session.status == .waiting, !view.viewer.isHost,
              let me = view.viewer.userId, view.session.originalHostUserId == me else { return }
        do {
            try await sessionService.returnToLobby(sessionId: sessionId)
        } catch {
            print("⚠️ [MultiplayerGameStore] Reclaiming the lobby failed: \(error.localizedDescription)")
        }
    }

    /// Asks the server to replace a silent host, at most once per tick and one claim at a
    /// time (with a time limit, like heartbeats). The server re-checks staleness on its own
    /// clock and installs its own successor, so a claim that lands late is harmless.
    func checkHost() {
        refreshHostOffline()
        guard isHostOffline, let sessionId, claimInFlight != sessionId else { return }
        claimInFlight = sessionId
        Task { [weak self, sessionService] in
            do {
                try await sessionService.claimHost(sessionId: sessionId)
            } catch {
                // HOST_ACTIVE / HOST_SUCCESSOR are expected races; the next tick asks again.
                print("⚠️ [MultiplayerGameStore] Host claim failed: \(error.localizedDescription)")
            }
            if self?.claimInFlight == sessionId { self?.claimInFlight = nil }
        }
    }

    func refreshHostOffline() {
        let offline = hostLooksOffline()
        if isHostOffline != offline { isHostOffline = offline }
    }

    /// The host's silence on the server's clock when `hostPresence` arrived, plus the local
    /// time since then; no device clock is compared with server time. While the socket is
    /// reconnecting or the server cannot identify me, I may be the one offline (and no new
    /// value can arrive), so nothing is concluded.
    func hostLooksOffline(now: ContinuousClock.Instant = .now) -> Bool {
        guard sessionId != nil, !isHost, !isSocketConnecting, !needsSignIn, sessionView?.viewer.isMember == true,
              let presence = hostPresence, let receivedAt = hostPresenceReceivedAt else { return false }
        let elapsed = receivedAt.duration(to: now)
        let age = presence.silenceAtReceipt
            + Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        return age > presence.staleAfterSeconds
    }

    /// Back from a time in which no presence value could arrive (suspended, socket down,
    /// unidentified): the host's silence counts on from now instead of adding the time away,
    /// until a fresh value replaces it. A host that really went quiet is still found once its
    /// silence passes the limit.
    func restartHostPresenceClock() {
        if hostPresenceReceivedAt != nil { hostPresenceReceivedAt = .now }
    }
}

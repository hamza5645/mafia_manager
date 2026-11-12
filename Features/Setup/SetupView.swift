import SwiftUI

/// One editable row of the Setup name list. The id keeps a row's identity (removal animation,
/// focus) attached to the row, not to its position, when other rows are removed or moved.
struct PlayerEntry: Identifiable, Equatable {
    /// Longest name a player can type
    static let maxNameLength = 30

    let id = UUID()
    var name: String
}

struct SetupView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var authStore: AuthStore
    private let minPlayers = 4
    private let maxPlayers = 19
    @State private var entries: [PlayerEntry] = [PlayerEntry(name: "")]
    @FocusState private var focusedEntryID: UUID?
    @State private var isAddingPlayer = false
    @State private var showLoadGroupSheet = false
    @State private var showLoadRoleConfigSheet = false
    @State private var playerGroups: [PlayerGroup] = []
    @State private var customRoleConfigs: [CustomRoleConfig] = []
    @State private var selectedRoleConfig: CustomRoleConfig?
    @State private var isLoadingGroups = false
    @State private var isLoadingConfigs = false
    @State private var groupsLoadError: String?
    @State private var configsLoadError: String?
    /// Bumped by a sheet's Retry button; restarts that sheet's load task.
    @State private var groupsLoadAttempt = 0
    @State private var configsLoadAttempt = 0
    @State private var numberOfBots: Int = 0
    /// One line of the name field's font; it grows with Dynamic Type, so the list height does too
    @ScaledMetric(relativeTo: .body) private var nameLineHeight: CGFloat = 22
    private let databaseService = DatabaseService()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header
                playersCard
                BotCounterCard(numberOfBots: $numberOfBots, canAddBot: validInput.count + numberOfBots < maxPlayers)
            }
            .readableContentWidth()
            // Add actual bottom padding to prevent overlap with bottom buttons
            // Extra padding for authenticated users who have more buttons (Load Group + Load Roles + Continue)
            // Using Color.clear with explicit height to ensure proper spacing at bottom
            Color.clear
                .frame(height: authStore.isAuthenticated ? 220 : 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Design.Colors.surface0)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if store.isFreshSetup {
                // Check if we have previous player info from "Play Again"
                if !store.previousPlayerNames.isEmpty || store.previousBotCount > 0 {
                    loadPreviousPlayers(animated: false)
                } else {
                    resetNameFields(animated: false)
                }
            }
        }
        .onChange(of: store.isFreshSetup) { _, fresh in
            if fresh {
                // Check if we have previous player info from "Play Again"
                if !store.previousPlayerNames.isEmpty || store.previousBotCount > 0 {
                    loadPreviousPlayers()
                } else {
                    resetNameFields()
                }
            }
        }
        .alert("Setup Error", isPresented: Binding(
            get: { store.setupError != nil },
            set: { presented in
                if !presented {
                    store.setupError = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                store.setupError = nil
            }
        } message: {
            Text(store.setupError ?? "Something went wrong.")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SetupBottomBar(
                // Hidden while a name is being edited, so the field stays visible above the keyboard
                showsLoadButtons: authStore.isAuthenticated && focusedEntryID == nil,
                roleConfigName: selectedRoleConfig?.configName,
                canContinue: isValid,
                playerCount: validInput.count + numberOfBots,
                onLoadGroup: { showLoadGroupSheet = true },
                onLoadRoles: { showLoadRoleConfigSheet = true },
                onContinue: {
                    store.assignNumbersAndRoles(names: validInput, numberOfBots: numberOfBots, customRoleConfig: selectedRoleConfig)
                }
            )
        }
        .task(id: isAddingPlayer) {
            // Allow removals again once the insertion animation has settled
            guard isAddingPlayer else { return }
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            isAddingPlayer = false
        }
        .sheet(isPresented: $showLoadGroupSheet) {
            LoadPlayerGroupSheet(
                playerGroups: playerGroups,
                isLoading: isLoadingGroups,
                loadError: groupsLoadError,
                onRetry: { groupsLoadAttempt += 1 },
                onSelect: { group in
                    loadGroup(group)
                    showLoadGroupSheet = false
                }
            )
            .task(id: groupsLoadAttempt) {
                await loadPlayerGroups()
            }
        }
        .sheet(isPresented: $showLoadRoleConfigSheet) {
            LoadCustomRoleConfigSheet(
                customRoleConfigs: customRoleConfigs,
                isLoading: isLoadingConfigs,
                loadError: configsLoadError,
                selectedConfig: selectedRoleConfig,
                totalPlayerCount: validInput.count + numberOfBots,
                onRetry: { configsLoadAttempt += 1 },
                onSelect: { config in
                    selectedRoleConfig = config
                    showLoadRoleConfigSheet = false
                },
                onClearSelection: {
                    selectedRoleConfig = nil
                    showLoadRoleConfigSheet = false
                }
            )
            .task(id: configsLoadAttempt) {
                await loadCustomRoleConfigs()
            }
        }
    }

    // MARK: - Sections

    // Enhanced Title Section with Gradient
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MAFIA")
                .font(Design.Typography.largeTitle)
                .kerning(1.5)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Design.Colors.brandGold, Design.Colors.brandGoldBright],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: Design.Colors.glowGold, radius: 10, y: 2)

            Text("Enter player names to begin")
                .font(Design.Typography.body)
                .foregroundStyle(Design.Colors.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // Players Card
    private var playersCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            let totalPlayers = validInput.count + numberOfBots

            Text("Between \(minPlayers) and \(maxPlayers) total players (humans + bots). Names must be unique.")
                .font(Design.Typography.footnote)
                .foregroundStyle(Design.Colors.textSecondary)

            if totalPlayers < minPlayers {
                Text("Add \(minPlayers - totalPlayers) more player(s) to start.")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.dangerRed.opacity(0.8))
            }

            // Player list with drag-and-drop reordering
            List {
                ForEach($entries) { $entry in
                    PlayerNameRow(
                        entry: $entry,
                        number: (entries.firstIndex { $0.id == entry.id } ?? 0) + 1,
                        focus: $focusedEntryID,
                        canRemove: entries.count > 1,
                        isRemovalDisabled: isAddingPlayer,
                        onRemove: { removeEntry(id: entry.id) }
                    )
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                }
                .onMove { offsets, offset in
                    withAnimation(Design.Animations.smooth) {
                        entries.move(fromOffsets: offsets, toOffset: offset)
                    }
                }
            }
            .listStyle(.plain)
            .scrollDisabled(true)
            // Each row is one text line + 28 pt field padding + 12 pt row insets (+2 pt slack)
            .frame(height: CGFloat(entries.count) * (nameLineHeight + 42))

            addPlayerRow
                .padding(.top, 8)
        }
        .cardStyle(padding: 20)
        .padding(.horizontal, 20)
    }

    // Improved bottom control section
    private var addPlayerRow: some View {
        HStack(spacing: 16) {
            let filled = entries.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
            let allFilled = filled == entries.count && filled >= minPlayers
            let isFull = entries.count >= maxPlayers

            Button {
                if !isFull {
                    isAddingPlayer = true
                    withAnimation(Design.Animations.smooth) {
                        entries.append(PlayerEntry(name: ""))
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(Design.Typography.body)
                    Text("Add Player")
                        .font(Design.Typography.subheadline)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Design.Colors.actionBlue.opacity(isFull ? 0.3 : 0.2))
                .cornerRadius(Design.Radii.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radii.medium, style: .continuous)
                        .stroke(Design.Colors.actionBlue.opacity(isFull ? 0.3 : 0.6), lineWidth: 1.5)
                )
            }
            .foregroundStyle(Design.Colors.actionBlue.opacity(isFull ? 0.5 : 1))
            .disabled(isFull)
            .accessibilityLabel("Add player")
            .accessibilityHint("Adds a new player slot")
            .automationID("solo.setup.addPlayer")

            Spacer()

            // Cleaner player count indicator
            HStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .font(Design.Typography.callout)
                    .accessibilityHidden(true)
                Text("\(entries.count)\(numberOfBots > 0 ? "+\(numberOfBots)" : "")/\(maxPlayers)")
                    .font(Design.Typography.subheadline)
            }
            .foregroundStyle(allFilled ? Design.Colors.successGreen : Design.Colors.textTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Design.Colors.surface2)
            .cornerRadius(Design.Radii.medium)
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radii.medium, style: .continuous)
                    .stroke(allFilled ? Design.Colors.successGreen.opacity(0.5) : Design.Colors.stroke.opacity(0.3), lineWidth: 1.5)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(entries.count + numberOfBots) of \(maxPlayers) players")
        }
    }

    // MARK: - State

    private var validInput: [String] {
        let trimmed = entries.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        // Remove duplicates while preserving order
        var seen = Set<String>()
        return trimmed.filter { seen.insert($0).inserted }
    }

    private var isValid: Bool {
        let trimmed = entries.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let totalPlayers = trimmed.count + numberOfBots

        // Must have at least minPlayers total (humans + bots)
        guard totalPlayers >= minPlayers && totalPlayers <= maxPlayers else { return false }

        // Human names must be unique
        let set = Set(trimmed.map { $0.lowercased() })
        return set.count == trimmed.count
    }

    private func removeEntry(id: UUID) {
        if focusedEntryID == id {
            focusedEntryID = nil
        }
        withAnimation(Design.Animations.smooth) {
            entries.removeAll { $0.id == id }
        }
    }

    private func resetNameFields(animated: Bool = true) {
        isAddingPlayer = false
        let base = [PlayerEntry(name: "")]
        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0.25)) {
                entries = base
                numberOfBots = 0
            }
        } else {
            entries = base
            numberOfBots = 0
        }
    }

    private func loadPlayerGroups() async {
        guard authStore.currentUserId != nil else { return }

        isLoadingGroups = true

        do {
            playerGroups = try await databaseService.getPlayerGroups()
            groupsLoadError = nil
        } catch {
            // Keep the groups already loaded; the sheet shows the error with Retry
            if !Task.isCancelled {
                groupsLoadError = error.localizedDescription
            }
        }

        isLoadingGroups = false
    }

    private func loadGroup(_ group: PlayerGroup) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0.25)) {
            entries = group.playerNames.map { PlayerEntry(name: $0) }
        }
    }

    private func loadPreviousPlayers(animated: Bool = true) {
        let previousNames = store.previousPlayerNames
        let previousBots = store.previousBotCount
        let targetNames = previousNames.isEmpty ? [""] : previousNames

        let applyChanges = {
            entries = targetNames.map { PlayerEntry(name: $0) }
            numberOfBots = previousBots
        }

        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0.25)) {
                applyChanges()
            }
        } else {
            applyChanges()
        }
        // Clear the previous data after loading so it doesn't persist
        store.previousPlayerNames = []
        store.previousBotCount = 0
    }

    private func loadCustomRoleConfigs() async {
        guard authStore.currentUserId != nil else { return }

        isLoadingConfigs = true

        do {
            customRoleConfigs = try await databaseService.getCustomRoleConfigs()
            configsLoadError = nil
        } catch {
            // Keep the configs already loaded; the sheet shows the error with Retry
            if !Task.isCancelled {
                configsLoadError = error.localizedDescription
            }
        }

        isLoadingConfigs = false
    }
}

// MARK: - Player Name Row

private struct PlayerNameRow: View {
    @Binding var entry: PlayerEntry
    let number: Int
    let focus: FocusState<UUID?>.Binding
    let canRemove: Bool
    let isRemovalDisabled: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Simplified player number badge
            ZStack {
                Circle()
                    .fill(Design.Colors.surface2)
                    .frame(width: 40, height: 40)

                Circle()
                    .stroke(Design.Colors.brandGold.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 40, height: 40)

                Text("\(number)")
                    .font(Design.Typography.subheadline)
                    .foregroundStyle(Design.Colors.brandGold)
            }

            // Streamlined text field
            TextField("Player Name", text: Binding(
                get: { entry.name },
                set: { newValue in
                    // Limit player names to 30 characters
                    entry.name = String(newValue.prefix(PlayerEntry.maxNameLength))
                }
            ))
            .focused(focus, equals: entry.id)
            .font(Design.Typography.body)
            .textInputAutocapitalization(.words)
            .disableAutocorrection(true)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Design.Colors.surface2)
            .cornerRadius(Design.Radii.medium)
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radii.medium, style: .continuous)
                    .stroke(Design.Colors.stroke.opacity(0.3), lineWidth: 1)
            )
            .accessibilityLabel("Player \(number) name")
            .accessibilityHint("Enter player name")
            .automationID("solo.setup.playerName.\(number)")

            if canRemove {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(Design.Typography.title2)
                        .foregroundStyle(Design.Colors.dangerRed.opacity(0.8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove player \(number)")
                .accessibilityHint("Removes this player from the game")
                .disabled(isRemovalDisabled)
                .opacity(isRemovalDisabled ? 0.3 : 1.0)
            }
        }
    }
}

// MARK: - Bot Counter Card

// Bot Players Section - Centered
private struct BotCounterCard: View {
    @Binding var numberOfBots: Int
    let canAddBot: Bool

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "cpu.fill")
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Colors.brandGold)
                    .accessibilityHidden(true)
                Text("Bot Players")
                    .font(Design.Typography.headline)
                    .foregroundStyle(Design.Colors.textPrimary)
            }
            .accessibilityAddTraits(.isHeader)

            Text("Add computer-controlled players to fill out your game")
                .font(Design.Typography.footnote)
                .foregroundStyle(Design.Colors.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 24) {
                Button {
                    if numberOfBots > 0 {
                        withAnimation(Design.Animations.smooth) {
                            numberOfBots -= 1
                        }
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(Design.Typography.largeTitle)
                        .foregroundStyle(numberOfBots > 0 ? Design.Colors.brandGold : Design.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(numberOfBots == 0)
                .accessibilityLabel("Decrease bot count")
                .accessibilityHint("Reduces bot players by one")
                .automationID("solo.setup.decreaseBotCount")

                VStack(spacing: 4) {
                    Text("\(numberOfBots)")
                        .font(Design.Typography.largeTitle)
                        .foregroundStyle(Design.Colors.brandGold)
                        .frame(minWidth: 80)

                    Text(numberOfBots == 1 ? "Bot" : "Bots")
                        .font(Design.Typography.subheadline)
                        .foregroundStyle(Design.Colors.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(numberOfBots) bot \(numberOfBots == 1 ? "player" : "players")")

                Button {
                    if canAddBot {
                        withAnimation(Design.Animations.smooth) {
                            numberOfBots += 1
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(Design.Typography.largeTitle)
                        .foregroundStyle(canAddBot ? Design.Colors.brandGold : Design.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!canAddBot)
                .accessibilityLabel("Increase bot count")
                .accessibilityHint("Adds one bot player")
                .automationID("solo.setup.increaseBotCount")
            }
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 20)
        .padding(.horizontal, 20)
    }
}

// MARK: - Setup Bottom Bar

/// Pinned footer: Load Group and Load Roles (signed-in users), then Continue.
private struct SetupBottomBar: View {
    let showsLoadButtons: Bool
    let roleConfigName: String?
    let canContinue: Bool
    let playerCount: Int
    let onLoadGroup: () -> Void
    let onLoadRoles: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: Design.Spacing.sm) {
            if showsLoadButtons {
                loadButtons
            }

            // Continue button (full width)
            Button(action: onContinue) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(Design.Typography.body)
                    Text("Continue")
                        .font(Design.Typography.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle(kind: .primary))
            .disabled(!canContinue)
            .accessibilityLabel("Continue to role assignment")
            .accessibilityHint("Starts the game with \(playerCount) players")
            .automationID("solo.setup.continue")
        }
        .padding(.horizontal, Design.Spacing.lg)
        .padding(.vertical, Design.Spacing.md)
        .readableContentWidth()
        .background(
            ZStack {
                // Near-opaque background that extends to screen bottom; it alone casts the bar's shadow
                Design.Colors.surface0.opacity(0.98)
                    .shadow(color: .black.opacity(0.2), radius: 20, y: -5)
                    .ignoresSafeArea(edges: .bottom)

                // Top border gradient
                LinearGradient(
                    colors: [
                        Design.Colors.strokeLight.opacity(0.3),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        )
    }

    // Top row: Load Group & Load Roles
    private var loadButtons: some View {
        HStack(spacing: Design.Spacing.sm) {
            Button(action: onLoadGroup) {
                VStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                        .font(Design.Typography.title2)
                    Text("Load Group")
                        .font(Design.Typography.caption)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(CompactGridButtonStyle(kind: .secondary))
            .accessibilityLabel("Load player group")
            .accessibilityHint("Load saved player names")

            Button(action: onLoadRoles) {
                VStack(spacing: 8) {
                    Image(systemName: "person.2.badge.gearshape.fill")
                        .font(Design.Typography.title2)
                    Text(roleConfigName ?? "Load Roles")
                        .font(Design.Typography.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(CompactGridButtonStyle(kind: roleConfigName == nil ? .secondary : .accent))
            .accessibilityLabel(roleConfigName.map { "Role configuration: \($0)" } ?? "Load role configuration")
            .accessibilityHint("Load custom role distribution")
        }
    }
}

// MARK: - Load Error

/// Inline load failure with Retry. Shown instead of an empty state, so a failed load never
/// reads as "nothing saved".
private struct LoadErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Design.Typography.title2)
                .foregroundColor(Design.Colors.dangerRed)
                .accessibilityHidden(true)

            Text(message)
                .font(Design.Typography.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)

            Button(action: onRetry) {
                Text("Retry")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CTAButtonStyle(kind: .secondary))
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Design.Colors.surface1)
        .cornerRadius(Design.Radii.card)
    }
}

// MARK: - Load Player Group Sheet

struct LoadPlayerGroupSheet: View {
    let playerGroups: [PlayerGroup]
    let isLoading: Bool
    let loadError: String?
    let onRetry: () -> Void
    let onSelect: (PlayerGroup) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.surface0
                    .ignoresSafeArea()

                // Groups already loaded stay on screen while a reload runs or after it fails
                if !playerGroups.isEmpty {
                    groupList
                } else if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if let loadError {
                    LoadErrorView(message: loadError, onRetry: onRetry)
                        .padding()
                } else {
                    emptyState
                }
            }
            .navigationTitle("Load Player Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.fill")
                .font(Design.Typography.displayEmoji)
                .foregroundColor(.white.opacity(0.3))
                .accessibilityHidden(true)

            Text("No Saved Groups")
                .font(Design.Typography.title2)
                .foregroundColor(.white)

            Text("Create player groups in Settings")
                .font(Design.Typography.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No saved groups. Create player groups in Settings.")
    }

    private var groupList: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let loadError {
                    LoadErrorView(message: loadError, onRetry: onRetry)
                }

                ForEach(playerGroups) { group in
                    PlayerGroupRow(group: group) {
                        onSelect(group)
                    }
                }
            }
            .padding()
        }
    }
}

private struct PlayerGroupRow: View {
    let group: PlayerGroup
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(group.groupName)
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "person.3.fill")
                        Text("\(group.playerNames.count)")
                    }
                    .foregroundColor(Design.Colors.brandGold)
                    .font(.subheadline)
                }

                Text(group.playerNames.prefix(5).joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Design.Colors.surface1)
            .cornerRadius(Design.Radii.card)
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radii.card)
                    .stroke(Design.Colors.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Load Custom Role Config Sheet

struct LoadCustomRoleConfigSheet: View {
    let customRoleConfigs: [CustomRoleConfig]
    let isLoading: Bool
    let loadError: String?
    let selectedConfig: CustomRoleConfig?
    let totalPlayerCount: Int
    let onRetry: () -> Void
    let onSelect: (CustomRoleConfig) -> Void
    let onClearSelection: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.surface0
                    .ignoresSafeArea()

                // Configs already loaded stay on screen while a reload runs or after it fails
                if isLoading && customRoleConfigs.isEmpty {
                    ProgressView()
                        .tint(.white)
                } else {
                    configList
                }
            }
            .navigationTitle("Role Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var configList: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Default option - always shown first
                DefaultRoleConfigRow(isSelected: selectedConfig == nil, onSelect: onClearSelection)

                if let loadError {
                    LoadErrorView(message: loadError, onRetry: onRetry)
                }

                if !customRoleConfigs.isEmpty {
                    // Custom configs
                    ForEach(customRoleConfigs) { config in
                        RoleConfigRow(
                            config: config,
                            isSelected: selectedConfig?.id == config.id,
                            totalPlayerCount: totalPlayerCount
                        ) {
                            onSelect(config)
                        }
                    }
                } else if loadError == nil {
                    noConfigsState
                }
            }
            .padding()
        }
    }

    private var noConfigsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.badge.gearshape.fill")
                .font(Design.Typography.displayEmoji)
                .foregroundColor(.white.opacity(0.3))
                .padding(.top, 40)
                .accessibilityHidden(true)

            Text("No Custom Role Configs")
                .font(Design.Typography.title2)
                .foregroundColor(.white)

            Text("Create custom role configurations in Settings")
                .font(Design.Typography.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No custom role configurations. Create custom role configurations in Settings.")
    }
}

private struct DefaultRoleConfigRow: View {
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Default Role Distribution")
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Design.Colors.successGreen)
                    }
                }

                Text("Balanced roles based on player count")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Design.Colors.surface2 : Design.Colors.surface1)
            .cornerRadius(Design.Radii.card)
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radii.card)
                    .stroke(isSelected ? Design.Colors.brandGold : Design.Colors.stroke, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// A saved role configuration; only selectable when it matches the current player count.
private struct RoleConfigRow: View {
    let config: CustomRoleConfig
    let isSelected: Bool
    let totalPlayerCount: Int
    let onSelect: () -> Void

    private var isMatchingPlayerCount: Bool {
        config.roleDistribution.totalPlayers == totalPlayerCount
    }

    var body: some View {
        Button {
            if isMatchingPlayerCount {
                onSelect()
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                header

                HStack(spacing: 16) {
                    RoleCountBadge(role: .mafia, count: config.roleDistribution.mafiaCount, dimmed: !isMatchingPlayerCount)
                    RoleCountBadge(role: .doctor, count: config.roleDistribution.doctorCount, dimmed: !isMatchingPlayerCount)
                    RoleCountBadge(role: .inspector, count: config.roleDistribution.inspectorCount, dimmed: !isMatchingPlayerCount)
                    RoleCountBadge(role: .citizen, count: config.roleDistribution.citizenCount, dimmed: !isMatchingPlayerCount)
                }
                .font(.caption)

                if !isMatchingPlayerCount {
                    Text("⚠️ Requires exactly \(config.roleDistribution.totalPlayers) total players (currently \(totalPlayerCount) incl. bots)")
                        .font(.caption2)
                        .foregroundColor(Design.Colors.dangerRed.opacity(0.8))
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Design.Colors.surface2 : Design.Colors.surface1)
            .cornerRadius(Design.Radii.card)
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radii.card)
                    .stroke(isSelected ? Design.Colors.brandGold : Design.Colors.stroke, lineWidth: isSelected ? 2 : 1)
            )
            .opacity(isMatchingPlayerCount ? 1.0 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!isMatchingPlayerCount)
    }

    private var header: some View {
        HStack {
            Text(config.configName)
                .font(.headline)
                .foregroundColor(isMatchingPlayerCount ? .white : .white.opacity(0.5))

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "person.3.fill")
                Text("\(config.roleDistribution.totalPlayers)")
            }
            .foregroundColor(isMatchingPlayerCount ? Design.Colors.brandGold : .white.opacity(0.5))
            .font(.subheadline)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Design.Colors.successGreen)
            }
        }
    }
}

struct RoleCountBadge: View {
    let role: Role
    let count: Int
    let dimmed: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: role.symbolName)
            Text("\(count)")
        }
        .foregroundColor(dimmed ? role.accentColor.opacity(0.5) : role.accentColor)
    }
}

// Removed local GlassButtonStyle; using global CTAButtonStyle instead.

import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var authStore: AuthStore
    private let minPlayers = 4
    private let maxPlayers = 19
    @State private var names: [String]
    @State private var isAddingPlayer = false
    @State private var showLoadGroupSheet = false
    @State private var showLoadRoleConfigSheet = false
    @State private var playerGroups: [PlayerGroup] = []
    @State private var customRoleConfigs: [CustomRoleConfig] = []
    @State private var selectedRoleConfig: CustomRoleConfig?
    @State private var isLoadingGroups = false
    @State private var isLoadingConfigs = false
    @State private var numberOfBots: Int = 0
    private let databaseService = DatabaseService()

    init() {
        _names = State(initialValue: Array(repeating: "", count: 1))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Enhanced Title Section with Gradient
                VStack(alignment: .leading, spacing: 10) {
                    Text("MAFIA MANAGER")
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

                // Players Card
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
                        ForEach(names.indices, id: \.self) { idx in
                            HStack(spacing: 12) {
                                // Simplified player number badge
                                ZStack {
                                    Circle()
                                        .fill(Design.Colors.surface2)
                                        .frame(width: 40, height: 40)

                                    Circle()
                                        .stroke(Design.Colors.brandGold.opacity(0.3), lineWidth: 1.5)
                                        .frame(width: 40, height: 40)

                                    Text("\(idx + 1)")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(Design.Colors.brandGold)
                                }

                                // Streamlined text field
                                TextField("Player Name", text: Binding(
                                    get: { names[idx] },
                                    set: { newValue in
                                        // Limit player names to 30 characters
                                        names[idx] = String(newValue.prefix(30))
                                    }
                                ))
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

                                if names.count > 1 {
                                    Button {
                                        withAnimation(Design.Animations.smooth) {
                                            let removalIndex = names.index(names.startIndex, offsetBy: idx)
                                            names.remove(at: removalIndex)
                                        }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 24))
                                            .foregroundStyle(Design.Colors.dangerRed.opacity(0.8))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove row")
                                    .disabled(isAddingPlayer)
                                    .opacity(isAddingPlayer ? 0.3 : 1.0)
                                }
                            }
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
                                names.move(fromOffsets: offsets, toOffset: offset)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollDisabled(true)
                    .frame(height: CGFloat(names.count) * 64)

                    // Improved bottom control section
                    HStack(spacing: 16) {
                        let filled = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.count
                        let allFilled = filled == names.count && filled >= minPlayers

                        Button {
                            if names.count < maxPlayers {
                                isAddingPlayer = true
                                withAnimation(Design.Animations.smooth) {
                                    names.append("")
                                }
                                // Add a small delay before allowing removals again
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    isAddingPlayer = false
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 18))
                                Text("Add Player")
                                    .font(Design.Typography.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Design.Colors.actionBlue.opacity(names.count >= maxPlayers ? 0.3 : 0.2))
                            .cornerRadius(Design.Radii.medium)
                            .overlay(
                                RoundedRectangle(cornerRadius: Design.Radii.medium, style: .continuous)
                                    .stroke(Design.Colors.actionBlue.opacity(names.count >= maxPlayers ? 0.3 : 0.6), lineWidth: 1.5)
                            )
                        }
                        .foregroundStyle(Design.Colors.actionBlue.opacity(names.count >= maxPlayers ? 0.5 : 1))
                        .disabled(names.count >= maxPlayers)

                        Spacer()

                        // Cleaner player count indicator
                        HStack(spacing: 8) {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 16))
                            Text("\(names.count)\(numberOfBots > 0 ? "+\(numberOfBots)" : "")/\(maxPlayers)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
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
                    }
                    .padding(.top, 8)
                }
                .cardStyle(padding: 20)
                .padding(.horizontal, 20)

                // Bot Players Section - Centered
                VStack(alignment: .center, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "cpu.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Design.Colors.brandGold)
                        Text("Bot Players")
                            .font(Design.Typography.headline)
                            .foregroundStyle(Design.Colors.textPrimary)
                    }

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
                                .font(.system(size: 36))
                                .foregroundStyle(numberOfBots > 0 ? Design.Colors.brandGold : Design.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .disabled(numberOfBots == 0)

                        VStack(spacing: 4) {
                            Text("\(numberOfBots)")
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundStyle(Design.Colors.brandGold)
                                .frame(minWidth: 80)

                            Text(numberOfBots == 1 ? "Bot" : "Bots")
                                .font(Design.Typography.subheadline)
                                .foregroundStyle(Design.Colors.textSecondary)
                        }

                        Button {
                            let totalPlayers = validInput.count + numberOfBots
                            if totalPlayers < maxPlayers {
                                withAnimation(Design.Animations.smooth) {
                                    numberOfBots += 1
                                }
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle((validInput.count + numberOfBots) < maxPlayers ? Design.Colors.brandGold : Design.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .disabled((validInput.count + numberOfBots) >= maxPlayers)
                    }
                    .padding(.vertical, 12)
                }
                .frame(maxWidth: .infinity)
                .cardStyle(padding: 20)
                .padding(.horizontal, 20)
            }
            // Add actual bottom padding to prevent overlap with bottom buttons
            // Extra padding for authenticated users who have more buttons (Load Group + Load Roles + Continue)
            // Using Color.clear with explicit height to ensure proper spacing at bottom
            Color.clear
                .frame(height: authStore.isAuthenticated ? 220 : 120)
        }
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
        .onChange(of: store.isFreshSetup) { fresh in
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
            VStack(spacing: Design.Spacing.md) {
                // Enhanced grid layout for authenticated users
                if authStore.isAuthenticated {
                    VStack(spacing: Design.Spacing.sm) {
                        // Top row: Load Group & Load Roles
                        HStack(spacing: Design.Spacing.sm) {
                            Button {
                                showLoadGroupSheet = true
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "person.3.fill")
                                        .font(.system(size: 22, weight: .semibold))
                                    Text("Load Group")
                                        .font(Design.Typography.caption)
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(CompactGridButtonStyle(kind: .secondary))

                            Button {
                                showLoadRoleConfigSheet = true
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "person.2.badge.gearshape.fill")
                                        .font(.system(size: 22, weight: .semibold))
                                    Text(selectedRoleConfig == nil ? "Load Roles" : selectedRoleConfig!.configName)
                                        .font(Design.Typography.caption)
                                        .fontWeight(.semibold)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(CompactGridButtonStyle(kind: selectedRoleConfig == nil ? .secondary : .accent))
                        }

                        // Bottom row: Continue button (full width)
                        Button {
                            store.assignNumbersAndRoles(names: validInput, numberOfBots: numberOfBots, customRoleConfig: selectedRoleConfig)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Continue")
                                    .font(Design.Typography.headline)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CTAButtonStyle(kind: .primary))
                        .disabled(!isValid)
                    }
                } else {
                    // Enhanced non-authenticated users layout
                    Button {
                        store.assignNumbersAndRoles(names: validInput, numberOfBots: numberOfBots, customRoleConfig: selectedRoleConfig)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Continue")
                                .font(Design.Typography.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CTAButtonStyle(kind: .primary))
                    .disabled(!isValid)
                }
            }
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.vertical, Design.Spacing.md)
            .background(
                ZStack {
                    // Glassmorphic background that extends to screen bottom
                    Design.Colors.surface0.opacity(0.98)
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
            .shadow(color: .black.opacity(0.2), radius: 20, y: -5)
        }
        .sheet(isPresented: $showLoadGroupSheet) {
            LoadPlayerGroupSheet(
                playerGroups: playerGroups,
                isLoading: isLoadingGroups,
                onSelect: { group in
                    loadGroup(group)
                    showLoadGroupSheet = false
                }
            )
            .task {
                await loadPlayerGroups()
            }
        }
        .sheet(isPresented: $showLoadRoleConfigSheet) {
            LoadCustomRoleConfigSheet(
                customRoleConfigs: customRoleConfigs,
                isLoading: isLoadingConfigs,
                selectedConfig: selectedRoleConfig,
                totalPlayerCount: validInput.count + numberOfBots,
                onSelect: { config in
                    selectedRoleConfig = config
                    showLoadRoleConfigSheet = false
                },
                onClearSelection: {
                    selectedRoleConfig = nil
                    showLoadRoleConfigSheet = false
                }
            )
            .task {
                await loadCustomRoleConfigs()
            }
        }
    }

    private var validInput: [String] {
        let trimmed = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        // Remove duplicates while preserving order
        var seen = Set<String>()
        return trimmed.filter { seen.insert($0).inserted }
    }

    private var isValid: Bool {
        let trimmed = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let totalPlayers = trimmed.count + numberOfBots

        // Must have at least minPlayers total (humans + bots)
        guard totalPlayers >= minPlayers && totalPlayers <= maxPlayers else { return false }

        // Human names must be unique
        let set = Set(trimmed.map { $0.lowercased() })
        return set.count == trimmed.count
    }

    private func resetNameFields(animated: Bool = true) {
        isAddingPlayer = false
        let base = Array(repeating: "", count: 1)
        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0.25)) {
                names = base
                numberOfBots = 0
            }
        } else {
            names = base
            numberOfBots = 0
        }
    }

    private func loadPlayerGroups() async {
        guard let userId = authStore.currentUserId else { return }

        isLoadingGroups = true

        do {
            // WORKAROUND: Pass access token to database service
            databaseService.accessToken = authStore.accessToken
            playerGroups = try await databaseService.getPlayerGroups(userId: userId)
        } catch {
            // Silent fail - user can try again
            playerGroups = []
        }

        isLoadingGroups = false
    }

    private func loadGroup(_ group: PlayerGroup) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0.25)) {
            names = group.playerNames
        }
    }

    private func loadPreviousPlayers(animated: Bool = true) {
        let previousNames = store.previousPlayerNames
        let previousBots = store.previousBotCount
        let targetNames = previousNames.isEmpty ? [""] : previousNames

        let applyChanges = {
            names = targetNames
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
        guard let userId = authStore.currentUserId else { return }

        isLoadingConfigs = true

        do {
            // WORKAROUND: Pass access token to database service
            databaseService.accessToken = authStore.accessToken
            customRoleConfigs = try await databaseService.getCustomRoleConfigs(userId: userId)
        } catch {
            // Silent fail - user can try again
            customRoleConfigs = []
        }

        isLoadingConfigs = false
    }
}

// MARK: - Load Player Group Sheet

struct LoadPlayerGroupSheet: View {
    let playerGroups: [PlayerGroup]
    let isLoading: Bool
    let onSelect: (PlayerGroup) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.surface0
                    .ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if playerGroups.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.3))

                        Text("No Saved Groups")
                            .font(.title2.bold())
                            .foregroundColor(.white)

                        Text("Create player groups in Settings")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(playerGroups) { group in
                                Button {
                                    onSelect(group)
                                } label: {
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
                        .padding()
                    }
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
}

// MARK: - Load Custom Role Config Sheet

struct LoadCustomRoleConfigSheet: View {
    let customRoleConfigs: [CustomRoleConfig]
    let isLoading: Bool
    let selectedConfig: CustomRoleConfig?
    let totalPlayerCount: Int
    let onSelect: (CustomRoleConfig) -> Void
    let onClearSelection: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.surface0
                    .ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            // Default option - always shown first
                            Button {
                                onClearSelection()
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Default Role Distribution")
                                            .font(.headline)
                                            .foregroundColor(.white)

                                        Spacer()

                                        if selectedConfig == nil {
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
                                .background(selectedConfig == nil ? Design.Colors.surface2 : Design.Colors.surface1)
                                .cornerRadius(Design.Radii.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Design.Radii.card)
                                        .stroke(selectedConfig == nil ? Design.Colors.brandGold : Design.Colors.stroke, lineWidth: selectedConfig == nil ? 2 : 1)
                                )
                            }
                            .buttonStyle(.plain)

                            if customRoleConfigs.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "person.2.badge.gearshape.fill")
                                        .font(.system(size: 60))
                                        .foregroundColor(.white.opacity(0.3))
                                        .padding(.top, 40)

                                    Text("No Custom Role Configs")
                                        .font(.title2.bold())
                                        .foregroundColor(.white)

                                    Text("Create custom role configurations in Settings")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                }
                            } else {
                                // Custom configs
                                ForEach(customRoleConfigs) { config in
                                    let isMatchingPlayerCount = config.roleDistribution.totalPlayers == totalPlayerCount
                                    let isSelected = selectedConfig?.id == config.id

                                    Button {
                                        if isMatchingPlayerCount {
                                            onSelect(config)
                                        }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 8) {
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
                            }
                        }
                        .padding()
                    }
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

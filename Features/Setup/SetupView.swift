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
    private let databaseService = DatabaseService()

    init() {
        _names = State(initialValue: Array(repeating: "", count: minPlayers))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Enhanced Title Section with Gradient
                VStack(alignment: .leading, spacing: 8) {
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
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // Enhanced Names Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Between \(minPlayers) and \(maxPlayers) players. Names must be unique.")
                        .font(Design.Typography.footnote)
                        .foregroundStyle(Design.Colors.textSecondary)

                    if names.count == minPlayers {
                        Text("Minimum \(minPlayers) players required for gameplay.")
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.textTertiary)
                    }

                    // Player list with drag-and-drop support
                    List {
                        ForEach(names.indices, id: \.self) { idx in
                            HStack(spacing: 10) {
                                // Drag handle icon
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Design.Colors.textSecondary)
                                    .opacity(0.6)

                                // Enhanced player number badge
                                Text("\(idx + 1)")
                                    .font(Design.Typography.subheadline)
                                    .fontWeight(.bold)
                                    .frame(width: 36)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: Design.Radii.medium, style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: [Design.Colors.surface2, Design.Colors.surface3],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Design.Radii.medium, style: .continuous)
                                            .stroke(Design.Colors.stroke.opacity(0.5), lineWidth: 1)
                                    )
                                    .foregroundStyle(Design.Colors.brandGold)

                                // Enhanced text field
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
                                .padding(.vertical, 12)
                                .padding(.horizontal, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: Design.Radii.medium, style: .continuous)
                                        .fill(Design.Colors.surface2)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: Design.Radii.medium, style: .continuous)
                                        .stroke(Design.Colors.stroke.opacity(0.4), lineWidth: 1)
                                )

                                if names.count > minPlayers {
                                    Button {
                                        // Extra safety check to ensure we don't go below minimum
                                        if names.count > minPlayers {
                                            withAnimation(Design.Animations.smooth) {
                                                let removalIndex = names.index(names.startIndex, offsetBy: idx)
                                                names.remove(at: removalIndex)
                                                // Final safety check - if somehow we went below minimum, reset to minimum
                                                if names.count < minPlayers {
                                                    resetNameFields(animated: true)
                                                }
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundStyle(Design.Colors.dangerRed)
                                            .shadow(color: Design.Colors.glowRed.opacity(0.5), radius: 6)
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
                    .frame(height: CGFloat(names.count) * 70)

                    // Enhanced bottom control section
                    HStack(spacing: 12) {
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
                            Label("Add Player", systemImage: "plus.circle.fill")
                                .font(Design.Typography.subheadline)
                        }
                        .buttonStyle(PillButtonStyle(background: Design.Colors.actionBlue))
                        .opacity(names.count >= maxPlayers ? 0.5 : 1)
                        .disabled(names.count >= maxPlayers)

                        Spacer()

                        // Enhanced player count indicator
                        HStack(spacing: 6) {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 14))
                            Text("\(names.count)/\(maxPlayers)")
                                .font(Design.Typography.subheadline)
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(allFilled ? Design.Colors.successGreen : Design.Colors.dangerRed)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill((allFilled ? Design.Colors.successGreen : Design.Colors.dangerRed).opacity(0.15))
                        )
                        .overlay(
                            Capsule()
                                .stroke(allFilled ? Design.Colors.successGreen : Design.Colors.dangerRed, lineWidth: 1.5)
                        )
                    }
                }
                .cardStyle(padding: 18)
                .padding(.horizontal, 20)

                Spacer(minLength: 14)
            }
        }
        .background(Design.Colors.surface0)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(Design.Colors.brandGold)
                }
            }
        }
        .onAppear {
            if store.isFreshSetup {
                // Check if we have previous player names from "Play Again"
                if !store.previousPlayerNames.isEmpty {
                    loadPreviousPlayers(animated: false)
                } else {
                    resetNameFields(animated: false)
                }
            }
        }
        .onChange(of: store.isFreshSetup) { fresh in
            if fresh {
                // Check if we have previous player names from "Play Again"
                if !store.previousPlayerNames.isEmpty {
                    loadPreviousPlayers()
                } else {
                    resetNameFields()
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: Design.Spacing.md) {
                // Load Last Game (if available) with enhanced styling
                if store.hasSavedGame {
                    Button {
                        store.loadLastGame()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Load Last Game")
                                .font(Design.Typography.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CTAButtonStyle(kind: .secondary))
                }

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
                            store.assignNumbersAndRoles(names: validInput, customRoleConfig: selectedRoleConfig)
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
                        store.assignNumbersAndRoles(names: validInput, customRoleConfig: selectedRoleConfig)
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
                    // Glassmorphic background
                    Design.Colors.surface0.opacity(0.98)

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
                playerCount: validInput.count,
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
        guard trimmed.count >= minPlayers && trimmed.count <= maxPlayers else { return false }
        let set = Set(trimmed.map { $0.lowercased() })
        return set.count == trimmed.count
    }

    private func resetNameFields(animated: Bool = true) {
        isAddingPlayer = false
        let base = Array(repeating: "", count: minPlayers)
        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0.25)) {
                names = base
            }
        } else {
            names = base
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
        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0.25)) {
                names = previousNames
            }
        } else {
            names = previousNames
        }
        // Clear the previous names after loading so they don't persist
        store.previousPlayerNames = []
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
    let playerCount: Int
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
                                    let isMatchingPlayerCount = config.roleDistribution.totalPlayers == playerCount
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
                                                Text("⚠️ Requires exactly \(config.roleDistribution.totalPlayers) players (currently \(playerCount))")
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

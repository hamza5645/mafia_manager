import SwiftUI

struct CustomRolesView: View {
    @EnvironmentObject var authStore: AuthStore
    @State private var customConfigs: [CustomRoleConfig] = []
    @State private var isLoading = false
    @State private var showAddConfig = false
    @State private var errorMessage: String?
    private let databaseService = DatabaseService()

    var body: some View {
        ZStack {
            Design.Colors.surface0
                .ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(.white)
            } else if customConfigs.isEmpty {
                EmptyCustomRolesView()
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(customConfigs) { config in
                            CustomRoleConfigCard(
                                config: config,
                                onDelete: {
                                    await deleteConfig(config)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Custom Roles")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddConfig = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Design.Colors.brandGold)
                }
            }
        }
        .task {
            await loadConfigs()
        }
        .refreshable {
            await loadConfigs()
        }
        .sheet(isPresented: $showAddConfig) {
            AddCustomRoleConfigView(onSave: { await loadConfigs() })
                .environmentObject(authStore)
        }
    }

    private func loadConfigs() async {
        guard let userId = authStore.currentUserId else { return }

        isLoading = true
        errorMessage = nil

        do {
            customConfigs = try await databaseService.getCustomRoleConfigs(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func deleteConfig(_ config: CustomRoleConfig) async {
        do {
            try await databaseService.deleteCustomRoleConfig(id: config.id)
            await loadConfigs()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct EmptyCustomRolesView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))

            Text("No Custom Configs")
                .font(.title2.bold())
                .foregroundColor(.white)

            Text("Create custom role distributions for different game sizes")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

struct CustomRoleConfigCard: View {
    let config: CustomRoleConfig
    let onDelete: () async -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text(config.configName)
                    .font(.title3.bold())
                    .foregroundColor(.white)

                Spacer()

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(Design.Colors.dangerRed)
                }
            }

            // Total Players
            HStack {
                Text("Total Players:")
                    .foregroundColor(.white.opacity(0.7))

                Text("\(config.roleDistribution.totalPlayers)")
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Spacer()
            }
            .font(.subheadline)

            Divider()
                .background(.white.opacity(0.2))

            // Role Distribution
            VStack(spacing: 12) {
                RoleDistributionRow(role: .mafia, count: config.roleDistribution.mafiaCount)
                RoleDistributionRow(role: .doctor, count: config.roleDistribution.doctorCount)
                RoleDistributionRow(role: .inspector, count: config.roleDistribution.inspectorCount)
                RoleDistributionRow(role: .citizen, count: config.roleDistribution.citizenCount)
            }
        }
        .padding()
        .background(Design.Colors.surface1)
        .cornerRadius(Design.Radii.card)
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radii.card)
                .stroke(Design.Colors.stroke, lineWidth: 1)
        )
        .confirmationDialog("Delete Configuration", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    await onDelete()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this configuration?")
        }
    }
}

struct RoleDistributionRow: View {
    let role: Role
    let count: Int

    var body: some View {
        HStack {
            Image(systemName: role.symbolName)
                .foregroundColor(role.accentColor)
                .frame(width: 24)

            Text(role.displayName)
                .foregroundColor(.white)

            Spacer()

            Text("\(count)")
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
        .font(.body)
    }
}

struct AddCustomRoleConfigView: View {
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.dismiss) var dismiss
    @State private var configName = ""
    @State private var mafiaCount = 1
    @State private var doctorCount = 1
    @State private var inspectorCount = 1
    @State private var citizenCount = 4
    @State private var isLoading = false
    @State private var errorMessage: String?
    let onSave: () async -> Void
    private let databaseService = DatabaseService()

    private var totalPlayers: Int {
        mafiaCount + doctorCount + inspectorCount + citizenCount
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.surface0
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Config Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Configuration Name")
                                .font(.headline)
                                .foregroundColor(.white)

                            TextField("e.g., Small Game", text: $configName)
                                .padding()
                                .background(Design.Colors.surface1)
                                .foregroundColor(.white)
                                .cornerRadius(Design.Radii.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Design.Radii.card)
                                        .stroke(Design.Colors.stroke, lineWidth: 1)
                                )
                        }

                        // Total Players Display
                        HStack {
                            Text("Total Players:")
                                .foregroundColor(.white.opacity(0.7))

                            Text("\(totalPlayers)")
                                .fontWeight(.bold)
                                .foregroundColor(Design.Colors.brandGold)
                                .font(.title3)
                        }

                        // Role Counts
                        VStack(spacing: 16) {
                            RoleCountPicker(role: .mafia, count: $mafiaCount, range: 1...5)
                            RoleCountPicker(role: .doctor, count: $doctorCount, range: 0...2)
                            RoleCountPicker(role: .inspector, count: $inspectorCount, range: 0...2)
                            RoleCountPicker(role: .citizen, count: $citizenCount, range: 1...15)
                        }

                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(Design.Colors.dangerRed)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("New Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await saveConfig()
                        }
                    }
                    .disabled(configName.isEmpty || isLoading)
                }
            }
        }
    }

    private func saveConfig() async {
        guard let userId = authStore.currentUserId else { return }

        isLoading = true
        errorMessage = nil

        let roleDistribution = CustomRoleConfig.RoleDistribution(
            mafiaCount: mafiaCount,
            doctorCount: doctorCount,
            inspectorCount: inspectorCount,
            citizenCount: citizenCount,
            totalPlayers: totalPlayers
        )

        let newConfig = CustomRoleConfig(
            id: UUID(),
            userId: userId,
            configName: configName,
            roleDistribution: roleDistribution,
            createdAt: Date(),
            updatedAt: Date()
        )

        do {
            try await databaseService.createCustomRoleConfig(newConfig)
            await onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct RoleCountPicker: View {
    let role: Role
    @Binding var count: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack {
            Image(systemName: role.symbolName)
                .foregroundColor(role.accentColor)
                .frame(width: 30)

            Text(role.displayName)
                .foregroundColor(.white)
                .frame(width: 100, alignment: .leading)

            Spacer()

            Stepper(
                value: $count,
                in: range
            ) {
                Text("\(count)")
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(minWidth: 30)
            }
        }
        .padding()
        .background(Design.Colors.surface1)
        .cornerRadius(Design.Radii.card)
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radii.card)
                .stroke(Design.Colors.stroke, lineWidth: 1)
        )
    }
}

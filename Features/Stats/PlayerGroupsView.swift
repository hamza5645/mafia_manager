import SwiftUI

struct PlayerGroupsView: View {
    @EnvironmentObject var authStore: AuthStore
    @State private var playerGroups: [PlayerGroup] = []
    @State private var isLoading = false
    @State private var showAddGroup = false
    @State private var editingGroup: PlayerGroup?
    @State private var errorMessage: String?
    private let databaseService = DatabaseService()

    var body: some View {
        ZStack {
            Design.Colors.surface0
                .ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(.white)
            } else if playerGroups.isEmpty {
                EmptyPlayerGroupsView()
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(playerGroups) { group in
                            PlayerGroupCard(
                                group: group,
                                onEdit: {
                                    editingGroup = group
                                },
                                onDelete: {
                                    await deleteGroup(group)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Player Groups")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddGroup = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Design.Colors.brandGold)
                }
            }
        }
        .task {
            await loadGroups()
        }
        .refreshable {
            await loadGroups()
        }
        .sheet(isPresented: $showAddGroup) {
            AddPlayerGroupView(onSave: { await loadGroups() })
                .environmentObject(authStore)
        }
        .sheet(item: $editingGroup) { group in
            EditPlayerGroupView(group: group, onSave: { await loadGroups() })
                .environmentObject(authStore)
        }
    }

    private func loadGroups() async {
        guard let userId = authStore.currentUserId,
              authStore.isAuthenticated else {
            errorMessage = "You must be logged in to view player groups"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // WORKAROUND: Pass access token to database service
            databaseService.accessToken = authStore.accessToken
            playerGroups = try await databaseService.getPlayerGroups(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func deleteGroup(_ group: PlayerGroup) async {
        guard authStore.isAuthenticated else {
            errorMessage = "You must be logged in to delete player groups"
            return
        }

        do {
            // WORKAROUND: Pass access token to database service
            databaseService.accessToken = authStore.accessToken
            try await databaseService.deletePlayerGroup(id: group.id)
            await loadGroups()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct EmptyPlayerGroupsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))

            Text("No Saved Groups")
                .font(.title2.bold())
                .foregroundColor(.white)

            Text("Save groups of player names for quick setup")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

struct PlayerGroupCard: View {
    let group: PlayerGroup
    let onEdit: () -> Void
    let onDelete: () async -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text(group.groupName)
                    .font(.title3.bold())
                    .foregroundColor(.white)

                Spacer()

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .foregroundColor(Design.Colors.brandGold)
                }

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(Design.Colors.dangerRed)
                }
            }

            // Player Count
            HStack {
                Image(systemName: "person.3.fill")
                    .foregroundColor(Design.Colors.brandGold)

                Text("\(group.playerNames.count) players")
                    .foregroundColor(.white.opacity(0.7))

                Spacer()
            }
            .font(.subheadline)

            Divider()
                .background(.white.opacity(0.2))

            // Player Names
            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.playerNames, id: \.self) { name in
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 20)

                        Text(name)
                            .foregroundColor(.white)

                        Spacer()
                    }
                    .font(.body)
                }
            }
        }
        .padding()
        .background(Design.Colors.surface1)
        .cornerRadius(Design.Radii.card)
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radii.card)
                .stroke(Design.Colors.stroke, lineWidth: 1)
        )
        .confirmationDialog("Delete Group", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    await onDelete()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this player group?")
        }
    }
}

struct AddPlayerGroupView: View {
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.dismiss) var dismiss
    @State private var groupName = ""
    @State private var playerNames: [String] = ["", "", "", ""]
    @State private var isLoading = false
    @State private var errorMessage: String?
    let onSave: () async -> Void
    private let databaseService = DatabaseService()

    private var validPlayerNames: [String] {
        playerNames.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var canSave: Bool {
        !groupName.trimmingCharacters(in: .whitespaces).isEmpty &&
        validPlayerNames.count >= 4 &&
        validPlayerNames.count <= 19 &&
        Set(validPlayerNames.map { $0.lowercased() }).count == validPlayerNames.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.surface0
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Group Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Group Name")
                                .font(.headline)
                                .foregroundColor(.white)

                            TextField("e.g., Usual Squad", text: $groupName)
                                .padding()
                                .background(Design.Colors.surface1)
                                .foregroundColor(.white)
                                .cornerRadius(Design.Radii.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Design.Radii.card)
                                        .stroke(Design.Colors.stroke, lineWidth: 1)
                                )
                        }

                        // Player Count Display
                        HStack {
                            Text("Players:")
                                .foregroundColor(.white.opacity(0.7))

                            Text("\(validPlayerNames.count)")
                                .fontWeight(.bold)
                                .foregroundColor(validPlayerNames.count >= 4 ? Design.Colors.brandGold : Design.Colors.dangerRed)
                                .font(.title3)

                            Text("/ 19")
                                .foregroundColor(.white.opacity(0.5))
                                .font(.title3)
                        }

                        // Player Names
                        VStack(spacing: 12) {
                            ForEach(playerNames.indices, id: \.self) { index in
                                HStack {
                                    TextField("Player \(index + 1)", text: $playerNames[index])
                                        .padding()
                                        .background(Design.Colors.surface1)
                                        .foregroundColor(.white)
                                        .cornerRadius(Design.Radii.card)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Design.Radii.card)
                                                .stroke(Design.Colors.stroke, lineWidth: 1)
                                        )

                                    if index >= 4 {
                                        Button {
                                            playerNames.remove(at: index)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundColor(Design.Colors.dangerRed)
                                        }
                                    }
                                }
                            }

                            if playerNames.count < 19 {
                                Button {
                                    playerNames.append("")
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Add Player")
                                    }
                                    .foregroundColor(Design.Colors.brandGold)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Design.Colors.surface1)
                                    .cornerRadius(Design.Radii.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Design.Radii.card)
                                            .stroke(Design.Colors.stroke, lineWidth: 1)
                                    )
                                }
                            }
                        }

                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(Design.Colors.dangerRed)
                        }

                        if !canSave {
                            Text("Group name required. Need 4-19 unique players.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("New Player Group")
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
                            await saveGroup()
                        }
                    }
                    .disabled(!canSave || isLoading)
                }
            }
        }
    }

    private func saveGroup() async {
        guard let userId = authStore.currentUserId,
              authStore.isAuthenticated else {
            errorMessage = "You must be logged in to save player groups"
            return
        }

        isLoading = true
        errorMessage = nil

        let newGroup = PlayerGroup(
            id: UUID(),
            userId: userId,
            groupName: groupName,
            playerNames: validPlayerNames,
            createdAt: Date(),
            updatedAt: Date()
        )

        do {
            // WORKAROUND: Pass access token to database service
            databaseService.accessToken = authStore.accessToken
            try await databaseService.createPlayerGroup(newGroup)
            await onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct EditPlayerGroupView: View {
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.dismiss) var dismiss
    let group: PlayerGroup
    @State private var groupName = ""
    @State private var playerNames: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    let onSave: () async -> Void
    private let databaseService = DatabaseService()

    private var validPlayerNames: [String] {
        playerNames.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var canSave: Bool {
        !groupName.trimmingCharacters(in: .whitespaces).isEmpty &&
        validPlayerNames.count >= 4 &&
        validPlayerNames.count <= 19 &&
        Set(validPlayerNames.map { $0.lowercased() }).count == validPlayerNames.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.surface0
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Group Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Group Name")
                                .font(.headline)
                                .foregroundColor(.white)

                            TextField("e.g., Usual Squad", text: $groupName)
                                .padding()
                                .background(Design.Colors.surface1)
                                .foregroundColor(.white)
                                .cornerRadius(Design.Radii.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Design.Radii.card)
                                        .stroke(Design.Colors.stroke, lineWidth: 1)
                                )
                        }

                        // Player Count Display
                        HStack {
                            Text("Players:")
                                .foregroundColor(.white.opacity(0.7))

                            Text("\(validPlayerNames.count)")
                                .fontWeight(.bold)
                                .foregroundColor(validPlayerNames.count >= 4 ? Design.Colors.brandGold : Design.Colors.dangerRed)
                                .font(.title3)

                            Text("/ 19")
                                .foregroundColor(.white.opacity(0.5))
                                .font(.title3)
                        }

                        // Player Names
                        VStack(spacing: 12) {
                            ForEach(playerNames.indices, id: \.self) { index in
                                HStack {
                                    TextField("Player \(index + 1)", text: $playerNames[index])
                                        .padding()
                                        .background(Design.Colors.surface1)
                                        .foregroundColor(.white)
                                        .cornerRadius(Design.Radii.card)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Design.Radii.card)
                                                .stroke(Design.Colors.stroke, lineWidth: 1)
                                        )

                                    if index >= 4 {
                                        Button {
                                            playerNames.remove(at: index)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundColor(Design.Colors.dangerRed)
                                        }
                                    }
                                }
                            }

                            if playerNames.count < 19 {
                                Button {
                                    playerNames.append("")
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Add Player")
                                    }
                                    .foregroundColor(Design.Colors.brandGold)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Design.Colors.surface1)
                                    .cornerRadius(Design.Radii.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Design.Radii.card)
                                            .stroke(Design.Colors.stroke, lineWidth: 1)
                                    )
                                }
                            }
                        }

                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(Design.Colors.dangerRed)
                        }

                        if !canSave {
                            Text("Group name required. Need 4-19 unique players.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Edit Player Group")
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
                            await saveGroup()
                        }
                    }
                    .disabled(!canSave || isLoading)
                }
            }
            .onAppear {
                // Initialize with existing group data
                groupName = group.groupName
                playerNames = group.playerNames
                // Ensure we have at least 4 empty slots if needed
                while playerNames.count < 4 {
                    playerNames.append("")
                }
            }
        }
    }

    private func saveGroup() async {
        guard let userId = authStore.currentUserId,
              authStore.isAuthenticated else {
            errorMessage = "You must be logged in to save player groups"
            return
        }

        isLoading = true
        errorMessage = nil

        var updatedGroup = group
        updatedGroup.groupName = groupName
        updatedGroup.playerNames = validPlayerNames
        updatedGroup.updatedAt = Date()

        do {
            // WORKAROUND: Pass access token to database service
            databaseService.accessToken = authStore.accessToken
            try await databaseService.updatePlayerGroup(updatedGroup)
            await onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

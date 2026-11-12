import SwiftUI

struct PlayerGroupsView: View {
    @EnvironmentObject var authStore: AuthStore
    @State private var playerGroups: [PlayerGroup] = []
    @State private var isLoading = false
    @State private var showAddGroup = false
    @State private var editingGroup: PlayerGroup?
    @State private var errorMessage: String?
    /// A sheet's save ran out of time; the list reloads when the sheet closes.
    @State private var reloadAfterSheet = false
    private let databaseService = DatabaseService()

    var body: some View {
        ZStack {
            Design.Colors.surface0
                .ignoresSafeArea()

            if isLoading && playerGroups.isEmpty {
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
                    .readableContentWidth()
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
        .sheet(isPresented: $showAddGroup, onDismiss: reloadAfterTimedOutSave) {
            AddPlayerGroupView(onSave: upsert, onTimeout: { reloadAfterSheet = true })
                .environmentObject(authStore)
        }
        .sheet(item: $editingGroup, onDismiss: reloadAfterTimedOutSave) { group in
            EditPlayerGroupView(group: group, onSave: upsert, onTimeout: { reloadAfterSheet = true })
                .environmentObject(authStore)
        }
        .alert("Player Groups", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Reload") { Task { await loadGroups() } }
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Could not complete the request. Please try again.")
        }
    }

    private func loadGroups() async {
        guard authStore.isAuthenticated else {
            errorMessage = "You must be logged in to view player groups"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            playerGroups = try await databaseService.getPlayerGroups()
        } catch is CancellationError {
            // Left the screen; keep what is shown.
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// A save that ran out of time may still apply, so show what the server has.
    private func reloadAfterTimedOutSave() {
        guard reloadAfterSheet else { return }
        reloadAfterSheet = false
        Task { await loadGroups() }
    }

    /// Inserts or replaces the row the server returned, without a reload.
    private func upsert(_ group: PlayerGroup) {
        playerGroups.removeAll { $0.id == group.id }
        playerGroups.append(group)
        playerGroups.sort { $0.groupName.localizedCaseInsensitiveCompare($1.groupName) == .orderedAscending }
    }

    private func deleteGroup(_ group: PlayerGroup) async {
        guard authStore.isAuthenticated else {
            errorMessage = "You must be logged in to delete player groups"
            return
        }

        do {
            try await databaseService.deletePlayerGroup(id: group.id)
            playerGroups.removeAll { $0.id == group.id }
        } catch let error as BackendError where error.isTimeout {
            // It may still be deleted: show what the server has instead of this list.
            await loadGroups()
            if errorMessage == nil { errorMessage = error.message }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct EmptyPlayerGroupsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.fill")
                .font(Design.Typography.displayEmoji)
                .foregroundColor(.white.opacity(0.3))
                .accessibilityHidden(true)

            Text("No Saved Groups")
                .font(Design.Typography.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text("Save groups of player names for quick setup")
                .font(Design.Typography.subheadline)
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
                    .font(Design.Typography.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Spacer()

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(Design.Typography.body)
                        .foregroundColor(Design.Colors.brandGold)
                }
                .accessibilityLabel("Edit \(group.groupName)")

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(Design.Typography.body)
                        .foregroundColor(Design.Colors.dangerRed)
                }
                .accessibilityLabel("Delete \(group.groupName)")
            }

            // Player Count
            HStack {
                Image(systemName: "person.3.fill")
                    .foregroundColor(Design.Colors.brandGold)
                    .accessibilityHidden(true)

                Text("\(group.playerNames.count) players")
                    .foregroundColor(.white.opacity(0.7))

                Spacer()
            }
            .font(Design.Typography.subheadline)

            Divider()
                .background(.white.opacity(0.2))

            // Player Names
            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.playerNames, id: \.self) { name in
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 20)
                            .accessibilityHidden(true)

                        Text(name)
                            .foregroundColor(.white)

                        Spacer()
                    }
                    .font(Design.Typography.body)
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
    @State private var playerRows: [GroupPlayerRow] = (0..<4).map { _ in GroupPlayerRow(name: "") }
    @State private var isLoading = false
    @State private var errorMessage: String?
    let onSave: (PlayerGroup) -> Void
    /// The save ran out of time and may still apply.
    var onTimeout: () -> Void = {}
    private let databaseService = DatabaseService()

    private var validPlayerNames: [String] {
        playerRows.map(\.name).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
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
                        GroupPlayerRowsEditor(rows: $playerRows)

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
                    .readableContentWidth()
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
        guard authStore.isAuthenticated else {
            errorMessage = "You must be logged in to save player groups"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let saved = try await databaseService.createPlayerGroup(
                name: groupName,
                playerNames: validPlayerNames
            )
            onSave(saved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            if (error as? BackendError)?.isTimeout == true { onTimeout() }
        }

        isLoading = false
    }
}

struct EditPlayerGroupView: View {
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.dismiss) var dismiss
    let group: PlayerGroup
    @State private var groupName = ""
    @State private var playerRows: [GroupPlayerRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    let onSave: (PlayerGroup) -> Void
    /// The save ran out of time and may still apply.
    var onTimeout: () -> Void = {}
    private let databaseService = DatabaseService()

    private var validPlayerNames: [String] {
        playerRows.map(\.name).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
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
                        GroupPlayerRowsEditor(rows: $playerRows)

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
                    .readableContentWidth()
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
                playerRows = group.playerNames.map { GroupPlayerRow(name: $0) }
                // Ensure we have at least 4 empty slots if needed
                while playerRows.count < 4 {
                    playerRows.append(GroupPlayerRow(name: ""))
                }
            }
        }
    }

    private func saveGroup() async {
        guard authStore.isAuthenticated else {
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
            let saved = try await databaseService.updatePlayerGroup(updatedGroup)
            onSave(saved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            if (error as? BackendError)?.isTimeout == true { onTimeout() }
        }

        isLoading = false
    }
}

/// One editable player name. The id keeps each row's identity (and focus)
/// when another row is removed; positions would not.
private struct GroupPlayerRow: Identifiable {
    let id = UUID()
    var name: String
}

/// The player name fields shared by the Add and Edit group sheets.
private struct GroupPlayerRowsEditor: View {
    @Binding var rows: [GroupPlayerRow]

    var body: some View {
        VStack(spacing: 12) {
            ForEach($rows) { $row in
                let index = rows.firstIndex { $0.id == row.id } ?? 0
                HStack {
                    TextField("Player \(index + 1)", text: $row.name)
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
                            rows.removeAll { $0.id == row.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(Design.Colors.dangerRed)
                        }
                    }
                }
            }

            if rows.count < 19 {
                Button {
                    rows.append(GroupPlayerRow(name: ""))
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
    }
}

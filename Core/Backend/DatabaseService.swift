import Foundation
import ConvexMobile

/// The signed-in caller's saved data. The server scopes every call to the
/// caller, which ConvexService identifies through Clerk or the guest proof.
@MainActor
final class DatabaseService {
    private let convex = ConvexService.shared

    // MARK: - Player Stats

    func getPlayerStats() async throws -> [PlayerStats] {
        let stats: [PlayerStats] = try await convex.query("stats:listPlayerStats")
        return stats.sorted { $0.playerName.localizedCaseInsensitiveCompare($1.playerName) == .orderedAscending }
    }

    func getPlayerStat(playerName: String) async throws -> PlayerStats? {
        try await convex.query(
            "stats:getPlayerStat",
            with: ["player_name": playerName],
            as: PlayerStats?.self
        )
    }

    func deletePlayerStat(id: UUID) async throws {
        try await convex.mutation(
            "stats:deletePlayerStat",
            with: ["id": id.uuidString.lowercased()]
        )
    }

    /// Records one finished game for this player name. Not idempotent:
    /// a retry after a lost response counts the game twice.
    func upsertPlayerStat(
        playerName: String,
        role: Role,
        won: Bool,
        kills: Int
    ) async throws {
        let _: PlayerStats = try await convex.mutation(
            "stats:upsertPlayerStat",
            with: [
                "player_name": playerName,
                "role": role.rawValue,
                "won": won,
                "kills": Double(kills),
            ]
        )
    }

    // MARK: - Custom Role Configs

    func getCustomRoleConfigs() async throws -> [CustomRoleConfig] {
        let configs: [CustomRoleConfig] = try await convex.query("stats:listCustomRoleConfigs")
        return configs.sorted { $0.configName.localizedCaseInsensitiveCompare($1.configName) == .orderedAscending }
    }

    func createCustomRoleConfig(
        name: String,
        roleDistribution: CustomRoleConfig.RoleDistribution
    ) async throws {
        let _: CustomRoleConfig = try await convex.mutation(
            "stats:createCustomRoleConfig",
            with: [
                "config_name": name,
                "role_distribution": try ConvexJSON(roleDistribution),
            ]
        )
    }

    func updateCustomRoleConfig(_ config: CustomRoleConfig) async throws {
        let _: CustomRoleConfig = try await convex.mutation(
            "stats:updateCustomRoleConfig",
            with: [
                "id": config.id.uuidString.lowercased(),
                "config_name": config.configName,
                "role_distribution": try ConvexJSON(config.roleDistribution),
            ]
        )
    }

    func deleteCustomRoleConfig(id: UUID) async throws {
        try await convex.mutation(
            "stats:deleteCustomRoleConfig",
            with: ["id": id.uuidString.lowercased()]
        )
    }

    // MARK: - Player Groups

    func getPlayerGroups() async throws -> [PlayerGroup] {
        let groups: [PlayerGroup] = try await convex.query("stats:listPlayerGroups")
        return groups.sorted { $0.groupName.localizedCaseInsensitiveCompare($1.groupName) == .orderedAscending }
    }

    func createPlayerGroup(name: String, playerNames: [String]) async throws {
        let _: PlayerGroup = try await convex.mutation(
            "stats:createPlayerGroup",
            with: [
                "group_name": name,
                "player_names": try ConvexJSON(playerNames),
            ]
        )
    }

    func updatePlayerGroup(_ group: PlayerGroup) async throws {
        let _: PlayerGroup = try await convex.mutation(
            "stats:updatePlayerGroup",
            with: [
                "id": group.id.uuidString.lowercased(),
                "group_name": group.groupName,
                "player_names": try ConvexJSON(group.playerNames),
            ]
        )
    }

    func deletePlayerGroup(id: UUID) async throws {
        try await convex.mutation(
            "stats:deletePlayerGroup",
            with: ["id": id.uuidString.lowercased()]
        )
    }
}

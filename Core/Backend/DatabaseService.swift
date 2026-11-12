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

    // MARK: - Custom Role Configs

    func getCustomRoleConfigs() async throws -> [CustomRoleConfig] {
        let configs: [CustomRoleConfig] = try await convex.query("stats:listCustomRoleConfigs")
        return configs.sorted { $0.configName.localizedCaseInsensitiveCompare($1.configName) == .orderedAscending }
    }

    // Library edits are interactive: they give up after
    // `interactiveMutationTimeout` and say the change may still go through.

    @discardableResult
    func createCustomRoleConfig(
        name: String,
        roleDistribution: CustomRoleConfig.RoleDistribution
    ) async throws -> CustomRoleConfig {
        try await convex.mutation(
            "stats:createCustomRoleConfig",
            with: [
                "config_name": name,
                "role_distribution": try ConvexJSON(roleDistribution),
            ],
            timeout: ConvexService.interactiveMutationTimeout
        )
    }

    @discardableResult
    func updateCustomRoleConfig(_ config: CustomRoleConfig) async throws -> CustomRoleConfig {
        try await convex.mutation(
            "stats:updateCustomRoleConfig",
            with: [
                "id": config.id.uuidString.lowercased(),
                "config_name": config.configName,
                "role_distribution": try ConvexJSON(config.roleDistribution),
            ],
            timeout: ConvexService.interactiveMutationTimeout
        )
    }

    func deleteCustomRoleConfig(id: UUID) async throws {
        try await convex.mutation(
            "stats:deleteCustomRoleConfig",
            with: ["id": id.uuidString.lowercased()],
            timeout: ConvexService.interactiveMutationTimeout
        )
    }

    // MARK: - Player Groups

    func getPlayerGroups() async throws -> [PlayerGroup] {
        let groups: [PlayerGroup] = try await convex.query("stats:listPlayerGroups")
        return groups.sorted { $0.groupName.localizedCaseInsensitiveCompare($1.groupName) == .orderedAscending }
    }

    @discardableResult
    func createPlayerGroup(name: String, playerNames: [String]) async throws -> PlayerGroup {
        try await convex.mutation(
            "stats:createPlayerGroup",
            with: [
                "group_name": name,
                "player_names": try ConvexJSON(playerNames),
            ],
            timeout: ConvexService.interactiveMutationTimeout
        )
    }

    @discardableResult
    func updatePlayerGroup(_ group: PlayerGroup) async throws -> PlayerGroup {
        try await convex.mutation(
            "stats:updatePlayerGroup",
            with: [
                "id": group.id.uuidString.lowercased(),
                "group_name": group.groupName,
                "player_names": try ConvexJSON(group.playerNames),
            ],
            timeout: ConvexService.interactiveMutationTimeout
        )
    }

    func deletePlayerGroup(id: UUID) async throws {
        try await convex.mutation(
            "stats:deletePlayerGroup",
            with: ["id": id.uuidString.lowercased()],
            timeout: ConvexService.interactiveMutationTimeout
        )
    }
}

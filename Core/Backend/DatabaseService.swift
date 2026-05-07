import Foundation
import ConvexMobile

@MainActor
final class DatabaseService {
    private let convex = ConvexService.shared

    // MARK: - Player Stats

    func getPlayerStats(userId: UUID) async throws -> [PlayerStats] {
        let stats: [PlayerStats] = try await convex.query(
            "stats:listPlayerStats",
            with: ["user_id": userId.uuidString.lowercased()]
        )
        return stats.sorted { $0.playerName.localizedCaseInsensitiveCompare($1.playerName) == .orderedAscending }
    }

    func getPlayerStat(userId: UUID, playerName: String) async throws -> PlayerStats? {
        try await convex.query(
            "stats:getPlayerStat",
            with: [
                "user_id": userId.uuidString.lowercased(),
                "player_name": playerName,
            ],
            as: PlayerStats?.self
        )
    }

    func createPlayerStat(_ stat: PlayerStats) async throws {
        let _: PlayerStats = try await convex.mutation(
            "stats:createPlayerStat",
            with: [
                "id": stat.id.uuidString.lowercased(),
                "user_id": stat.userId.uuidString.lowercased(),
                "player_name": stat.playerName,
                "games_played": Double(stat.gamesPlayed),
                "games_won": Double(stat.gamesWon),
                "games_lost": Double(stat.gamesLost),
                "total_kills": Double(stat.totalKills),
                "times_mafia": Double(stat.timesMafia),
                "times_doctor": Double(stat.timesDoctor),
                "times_inspector": Double(stat.timesInspector),
                "times_citizen": Double(stat.timesCitizen),
            ]
        )
    }

    func updatePlayerStat(_ stat: PlayerStats) async throws {
        let _: PlayerStats = try await convex.mutation(
            "stats:updatePlayerStat",
            with: [
                "id": stat.id.uuidString.lowercased(),
                "games_played": Double(stat.gamesPlayed),
                "games_won": Double(stat.gamesWon),
                "games_lost": Double(stat.gamesLost),
                "total_kills": Double(stat.totalKills),
                "times_mafia": Double(stat.timesMafia),
                "times_doctor": Double(stat.timesDoctor),
                "times_inspector": Double(stat.timesInspector),
                "times_citizen": Double(stat.timesCitizen),
            ]
        )
    }

    func deletePlayerStat(id: UUID) async throws {
        try await convex.mutation("stats:deletePlayerStat", with: ["id": id.uuidString.lowercased()])
    }

    func upsertPlayerStat(userId: UUID, playerName: String, role: Role, won: Bool, kills: Int) async throws {
        let _: PlayerStats = try await convex.mutation(
            "stats:upsertPlayerStat",
            with: [
                "user_id": userId.uuidString.lowercased(),
                "player_name": playerName,
                "role": role.rawValue,
                "won": won,
                "kills": Double(kills),
            ]
        )
    }

    // MARK: - Custom Role Configs

    func getCustomRoleConfigs(userId: UUID) async throws -> [CustomRoleConfig] {
        let configs: [CustomRoleConfig] = try await convex.query(
            "stats:listCustomRoleConfigs",
            with: ["user_id": userId.uuidString.lowercased()]
        )
        return configs.sorted { $0.configName.localizedCaseInsensitiveCompare($1.configName) == .orderedAscending }
    }

    func getCustomRoleConfig(id: UUID) async throws -> CustomRoleConfig? {
        try await convex.query(
            "stats:getCustomRoleConfig",
            with: ["id": id.uuidString.lowercased()],
            as: CustomRoleConfig?.self
        )
    }

    func createCustomRoleConfig(_ config: CustomRoleConfig) async throws {
        let _: CustomRoleConfig = try await convex.mutation(
            "stats:createCustomRoleConfig",
            with: [
                "id": config.id.uuidString.lowercased(),
                "user_id": config.userId.uuidString.lowercased(),
                "config_name": config.configName,
                "role_distribution": roleDistributionArgs(config.roleDistribution),
            ]
        )
    }

    func updateCustomRoleConfig(_ config: CustomRoleConfig) async throws {
        let _: CustomRoleConfig = try await convex.mutation(
            "stats:updateCustomRoleConfig",
            with: [
                "id": config.id.uuidString.lowercased(),
                "config_name": config.configName,
                "role_distribution": roleDistributionArgs(config.roleDistribution),
            ]
        )
    }

    func deleteCustomRoleConfig(id: UUID) async throws {
        try await convex.mutation("stats:deleteCustomRoleConfig", with: ["id": id.uuidString.lowercased()])
    }

    // MARK: - Player Groups

    func getPlayerGroups(userId: UUID) async throws -> [PlayerGroup] {
        let groups: [PlayerGroup] = try await convex.query(
            "stats:listPlayerGroups",
            with: ["user_id": userId.uuidString.lowercased()]
        )
        return groups.sorted { $0.groupName.localizedCaseInsensitiveCompare($1.groupName) == .orderedAscending }
    }

    func getPlayerGroup(id: UUID) async throws -> PlayerGroup? {
        try await convex.query(
            "stats:getPlayerGroup",
            with: ["id": id.uuidString.lowercased()],
            as: PlayerGroup?.self
        )
    }

    func createPlayerGroup(_ group: PlayerGroup) async throws {
        let _: PlayerGroup = try await convex.mutation(
            "stats:createPlayerGroup",
            with: [
                "id": group.id.uuidString.lowercased(),
                "user_id": group.userId.uuidString.lowercased(),
                "group_name": group.groupName,
                "player_names": group.playerNames.map { $0 as ConvexEncodable? },
            ]
        )
    }

    func updatePlayerGroup(_ group: PlayerGroup) async throws {
        let _: PlayerGroup = try await convex.mutation(
            "stats:updatePlayerGroup",
            with: [
                "id": group.id.uuidString.lowercased(),
                "group_name": group.groupName,
                "player_names": group.playerNames.map { $0 as ConvexEncodable? },
            ]
        )
    }

    func deletePlayerGroup(id: UUID) async throws {
        try await convex.mutation("stats:deletePlayerGroup", with: ["id": id.uuidString.lowercased()])
    }

    private func roleDistributionArgs(_ distribution: CustomRoleConfig.RoleDistribution) -> [String: ConvexEncodable?] {
        [
            "mafia_count": Double(distribution.mafiaCount),
            "doctor_count": Double(distribution.doctorCount),
            "inspector_count": Double(distribution.inspectorCount),
            "citizen_count": Double(distribution.citizenCount),
            "total_players": Double(distribution.totalPlayers),
        ]
    }
}


import Foundation
import ConvexMobile

@MainActor
final class DatabaseService {
    private let convex = ConvexService.shared

    // MARK: - Player Stats

    func getPlayerStats(userId: UUID, guestSecretHash: String? = nil) async throws -> [PlayerStats] {
        let stats: [PlayerStats] = try await convex.query(
            "stats:listPlayerStats",
            with: [
                "user_id": userId.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ]
        )
        return stats.sorted { $0.playerName.localizedCaseInsensitiveCompare($1.playerName) == .orderedAscending }
    }

    func getPlayerStat(
        userId: UUID,
        playerName: String,
        guestSecretHash: String? = nil
    ) async throws -> PlayerStats? {
        try await convex.query(
            "stats:getPlayerStat",
            with: [
                "user_id": userId.uuidString.lowercased(),
                "player_name": playerName,
                "guest_secret_hash": guestSecretHash,
            ],
            as: PlayerStats?.self
        )
    }

    func createPlayerStat(_ stat: PlayerStats, guestSecretHash: String? = nil) async throws {
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
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func updatePlayerStat(_ stat: PlayerStats, guestSecretHash: String? = nil) async throws {
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
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func deletePlayerStat(id: UUID, guestSecretHash: String? = nil) async throws {
        try await convex.mutation(
            "stats:deletePlayerStat",
            with: [
                "id": id.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func upsertPlayerStat(
        userId: UUID,
        playerName: String,
        role: Role,
        won: Bool,
        kills: Int,
        guestSecretHash: String? = nil
    ) async throws {
        let _: PlayerStats = try await convex.mutation(
            "stats:upsertPlayerStat",
            with: [
                "user_id": userId.uuidString.lowercased(),
                "player_name": playerName,
                "role": role.rawValue,
                "won": won,
                "kills": Double(kills),
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    // MARK: - Custom Role Configs

    func getCustomRoleConfigs(
        userId: UUID,
        guestSecretHash: String? = nil
    ) async throws -> [CustomRoleConfig] {
        let configs: [CustomRoleConfig] = try await convex.query(
            "stats:listCustomRoleConfigs",
            with: [
                "user_id": userId.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ]
        )
        return configs.sorted { $0.configName.localizedCaseInsensitiveCompare($1.configName) == .orderedAscending }
    }

    func getCustomRoleConfig(id: UUID, guestSecretHash: String? = nil) async throws -> CustomRoleConfig? {
        try await convex.query(
            "stats:getCustomRoleConfig",
            with: [
                "id": id.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ],
            as: CustomRoleConfig?.self
        )
    }

    func createCustomRoleConfig(
        _ config: CustomRoleConfig,
        guestSecretHash: String? = nil
    ) async throws {
        let _: CustomRoleConfig = try await convex.mutation(
            "stats:createCustomRoleConfig",
            with: [
                "id": config.id.uuidString.lowercased(),
                "user_id": config.userId.uuidString.lowercased(),
                "config_name": config.configName,
                "role_distribution": roleDistributionArgs(config.roleDistribution),
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func updateCustomRoleConfig(
        _ config: CustomRoleConfig,
        guestSecretHash: String? = nil
    ) async throws {
        let _: CustomRoleConfig = try await convex.mutation(
            "stats:updateCustomRoleConfig",
            with: [
                "id": config.id.uuidString.lowercased(),
                "config_name": config.configName,
                "role_distribution": roleDistributionArgs(config.roleDistribution),
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func deleteCustomRoleConfig(id: UUID, guestSecretHash: String? = nil) async throws {
        try await convex.mutation(
            "stats:deleteCustomRoleConfig",
            with: [
                "id": id.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    // MARK: - Player Groups

    func getPlayerGroups(userId: UUID, guestSecretHash: String? = nil) async throws -> [PlayerGroup] {
        let groups: [PlayerGroup] = try await convex.query(
            "stats:listPlayerGroups",
            with: [
                "user_id": userId.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ]
        )
        return groups.sorted { $0.groupName.localizedCaseInsensitiveCompare($1.groupName) == .orderedAscending }
    }

    func getPlayerGroup(id: UUID, guestSecretHash: String? = nil) async throws -> PlayerGroup? {
        try await convex.query(
            "stats:getPlayerGroup",
            with: [
                "id": id.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ],
            as: PlayerGroup?.self
        )
    }

    func createPlayerGroup(_ group: PlayerGroup, guestSecretHash: String? = nil) async throws {
        let _: PlayerGroup = try await convex.mutation(
            "stats:createPlayerGroup",
            with: [
                "id": group.id.uuidString.lowercased(),
                "user_id": group.userId.uuidString.lowercased(),
                "group_name": group.groupName,
                "player_names": group.playerNames.map { $0 as ConvexEncodable? },
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func updatePlayerGroup(_ group: PlayerGroup, guestSecretHash: String? = nil) async throws {
        let _: PlayerGroup = try await convex.mutation(
            "stats:updatePlayerGroup",
            with: [
                "id": group.id.uuidString.lowercased(),
                "group_name": group.groupName,
                "player_names": group.playerNames.map { $0 as ConvexEncodable? },
                "guest_secret_hash": guestSecretHash,
            ]
        )
    }

    func deletePlayerGroup(id: UUID, guestSecretHash: String? = nil) async throws {
        try await convex.mutation(
            "stats:deletePlayerGroup",
            with: [
                "id": id.uuidString.lowercased(),
                "guest_secret_hash": guestSecretHash,
            ]
        )
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

import Foundation
import Supabase
import PostgREST

@MainActor
final class DatabaseService {
    private let supabase = SupabaseService.shared.client

    // WORKAROUND: Access token to manually attach to requests
    var accessToken: String?

    // MARK: - Player Stats

    func getPlayerStats(userId: UUID) async throws -> [PlayerStats] {
        let response: [PlayerStats] = try await supabase
            .from("player_stats")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("player_name")
            .execute()
            .value

        return response
    }

    func getPlayerStat(userId: UUID, playerName: String) async throws -> PlayerStats? {
        let response: [PlayerStats] = try await supabase
            .from("player_stats")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("player_name", value: playerName)
            .execute()
            .value

        return response.first
    }

    func createPlayerStat(_ stat: PlayerStats) async throws {
        try await supabase
            .from("player_stats")
            .insert(stat)
            .execute()
    }

    func updatePlayerStat(_ stat: PlayerStats) async throws {
        struct UpdateData: Encodable {
            let gamesPlayed: Int
            let gamesWon: Int
            let gamesLost: Int
            let totalKills: Int
            let timesMafia: Int
            let timesDoctor: Int
            let timesInspector: Int
            let timesCitizen: Int
            let updatedAt: Date

            enum CodingKeys: String, CodingKey {
                case gamesPlayed = "games_played"
                case gamesWon = "games_won"
                case gamesLost = "games_lost"
                case totalKills = "total_kills"
                case timesMafia = "times_mafia"
                case timesDoctor = "times_doctor"
                case timesInspector = "times_inspector"
                case timesCitizen = "times_citizen"
                case updatedAt = "updated_at"
            }
        }

        let updateData = UpdateData(
            gamesPlayed: stat.gamesPlayed,
            gamesWon: stat.gamesWon,
            gamesLost: stat.gamesLost,
            totalKills: stat.totalKills,
            timesMafia: stat.timesMafia,
            timesDoctor: stat.timesDoctor,
            timesInspector: stat.timesInspector,
            timesCitizen: stat.timesCitizen,
            updatedAt: Date()
        )

        try await supabase
            .from("player_stats")
            .update(updateData)
            .eq("id", value: stat.id.uuidString)
            .execute()
    }

    func deletePlayerStat(id: UUID) async throws {
        try await supabase
            .from("player_stats")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // Upsert player stats (create if not exists, update if exists)
    func upsertPlayerStat(userId: UUID, playerName: String, role: Role, won: Bool, kills: Int) async throws {
        if let existingStat = try await getPlayerStat(userId: userId, playerName: playerName) {
            // Update existing stat
            var updatedStat = existingStat
            updatedStat.gamesPlayed += 1
            if won {
                updatedStat.gamesWon += 1
            } else {
                updatedStat.gamesLost += 1
            }
            updatedStat.totalKills += kills

            switch role {
            case .mafia:
                updatedStat.timesMafia += 1
            case .doctor:
                updatedStat.timesDoctor += 1
            case .inspector:
                updatedStat.timesInspector += 1
            case .citizen:
                updatedStat.timesCitizen += 1
            }

            try await updatePlayerStat(updatedStat)
        } else {
            // Create new stat
            let newStat = PlayerStats(
                id: UUID(),
                userId: userId,
                playerName: playerName,
                gamesPlayed: 1,
                gamesWon: won ? 1 : 0,
                gamesLost: won ? 0 : 1,
                totalKills: kills,
                timesMafia: role == .mafia ? 1 : 0,
                timesDoctor: role == .doctor ? 1 : 0,
                timesInspector: role == .inspector ? 1 : 0,
                timesCitizen: role == .citizen ? 1 : 0,
                createdAt: Date(),
                updatedAt: Date()
            )

            try await createPlayerStat(newStat)
        }
    }

    // MARK: - Custom Role Configs

    func getCustomRoleConfigs(userId: UUID) async throws -> [CustomRoleConfig] {
        // WORKAROUND: Manually attach auth token to request
        var request = try supabase
            .from("custom_roles_configs")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("config_name")

        if let token = accessToken {
            request = request.setHeader(name: "Authorization", value: "Bearer \(token)")
        }

        let response: [CustomRoleConfig] = try await request
            .execute()
            .value

        return response
    }

    func getCustomRoleConfig(id: UUID) async throws -> CustomRoleConfig? {
        // WORKAROUND: Manually attach auth token to request
        var request = try supabase
            .from("custom_roles_configs")
            .select()
            .eq("id", value: id.uuidString)

        if let token = accessToken {
            request = request.setHeader(name: "Authorization", value: "Bearer \(token)")
        }

        let response: [CustomRoleConfig] = try await request
            .execute()
            .value

        return response.first
    }

    func createCustomRoleConfig(_ config: CustomRoleConfig) async throws {
        // WORKAROUND: Manually attach auth token to request
        var request = try supabase
            .from("custom_roles_configs")
            .insert(config)

        if let token = accessToken {
            request = request.setHeader(name: "Authorization", value: "Bearer \(token)")
        }

        try await request.execute()
    }

    func updateCustomRoleConfig(_ config: CustomRoleConfig) async throws {
        struct UpdateData: Encodable {
            let configName: String
            let roleDistribution: CustomRoleConfig.RoleDistribution
            let updatedAt: Date

            enum CodingKeys: String, CodingKey {
                case configName = "config_name"
                case roleDistribution = "role_distribution"
                case updatedAt = "updated_at"
            }
        }

        let updateData = UpdateData(
            configName: config.configName,
            roleDistribution: config.roleDistribution,
            updatedAt: Date()
        )

        // WORKAROUND: Manually attach auth token to request
        var request = try supabase
            .from("custom_roles_configs")
            .update(updateData)
            .eq("id", value: config.id.uuidString)

        if let token = accessToken {
            request = request.setHeader(name: "Authorization", value: "Bearer \(token)")
        }

        try await request.execute()
    }

    func deleteCustomRoleConfig(id: UUID) async throws {
        // WORKAROUND: Manually attach auth token to request
        var request = try supabase
            .from("custom_roles_configs")
            .delete()
            .eq("id", value: id.uuidString)

        if let token = accessToken {
            request = request.setHeader(name: "Authorization", value: "Bearer \(token)")
        }

        try await request.execute()
    }

    // MARK: - Player Groups

    func getPlayerGroups(userId: UUID) async throws -> [PlayerGroup] {
        // WORKAROUND: Manually attach auth token to request
        var request = try supabase
            .from("player_groups")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("group_name")

        if let token = accessToken {
            request = request.setHeader(name: "Authorization", value: "Bearer \(token)")
        }

        let response: [PlayerGroup] = try await request
            .execute()
            .value

        return response
    }

    func getPlayerGroup(id: UUID) async throws -> PlayerGroup? {
        // WORKAROUND: Manually attach auth token to request
        var request = try supabase
            .from("player_groups")
            .select()
            .eq("id", value: id.uuidString)

        if let token = accessToken {
            request = request.setHeader(name: "Authorization", value: "Bearer \(token)")
        }

        let response: [PlayerGroup] = try await request
            .execute()
            .value

        return response.first
    }

    func createPlayerGroup(_ group: PlayerGroup) async throws {
        // WORKAROUND: Manually attach auth token to request
        var request = try supabase
            .from("player_groups")
            .insert(group)

        if let token = accessToken {
            request = request.setHeader(name: "Authorization", value: "Bearer \(token)")
        }

        try await request.execute()
    }

    func updatePlayerGroup(_ group: PlayerGroup) async throws {
        struct UpdateData: Encodable {
            let groupName: String
            let playerNames: [String]
            let updatedAt: Date

            enum CodingKeys: String, CodingKey {
                case groupName = "group_name"
                case playerNames = "player_names"
                case updatedAt = "updated_at"
            }
        }

        let updateData = UpdateData(
            groupName: group.groupName,
            playerNames: group.playerNames,
            updatedAt: Date()
        )

        // WORKAROUND: Manually attach auth token to request
        var request = try supabase
            .from("player_groups")
            .update(updateData)
            .eq("id", value: group.id.uuidString)

        if let token = accessToken {
            request = request.setHeader(name: "Authorization", value: "Bearer \(token)")
        }

        try await request.execute()
    }

    func deletePlayerGroup(id: UUID) async throws {
        // WORKAROUND: Manually attach auth token to request
        var request = try supabase
            .from("player_groups")
            .delete()
            .eq("id", value: id.uuidString)

        if let token = accessToken {
            request = request.setHeader(name: "Authorization", value: "Bearer \(token)")
        }

        try await request.execute()
    }
}

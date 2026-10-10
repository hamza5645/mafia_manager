import Foundation
import Testing

@testable import mafia_manager

struct MultiplayerModelDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func voteCountsDecodeFromAnObject() throws {
        let leader = UUID()
        let other = UUID()
        let data = try decode(PhaseData.self, """
        {"type":"votingResults","dayIndex":2,
         "voteCounts":{"\(leader.uuidString.lowercased())":3,"\(other.uuidString.lowercased())":0,"not-a-uuid":9},
         "eliminatedPlayerId":"\(leader.uuidString.lowercased())"}
        """)
        #expect(data == .votingResults(dayIndex: 2, voteCounts: [leader: 3, other: 0], eliminatedPlayerId: leader))
    }

    @Test func voteCountsDecodeFromTheLegacyAlternatingArray() throws {
        let leader = UUID()
        let other = UUID()
        // Games started before api_contract 4 stored Swift's Dictionary<UUID, Int> encoding.
        let data = try decode(PhaseData.self, """
        {"type":"votingResults","dayIndex":1,"voteCounts":["\(leader.uuidString)",2,"\(other.uuidString)",1]}
        """)
        #expect(data == .votingResults(dayIndex: 1, voteCounts: [leader: 2, other: 1], eliminatedPlayerId: nil))
    }

    @Test func sessionViewDecodesViewerAndProjectedSession() throws {
        let session = UUID().uuidString.lowercased()
        let host = UUID().uuidString.lowercased()
        let view = try decode(SessionView.self, """
        {"session":{"id":"\(session)","room_code":"123456","host_user_id":"\(host)","original_host_user_id":"\(host)",
          "status":"in_progress","created_at":1000,"max_players":19,"bot_count":2,"current_phase":"night",
          "current_phase_data":{"type":"night","nightIndex":0},"day_index":0,"is_game_over":false,
          "assigned_numbers":[],"night_history":[{"night_index":0,"is_resolved":true,"resulting_deaths":[],
          "revealed_death_roles":{},"timestamp":1001,"round_id":"r","next_phase":"morning"}],"day_history":[],
          "current_round_id":"\(session)","updated_at":1002},
         "viewer":{"user_id":"\(host)","player_record_id":null,"player_id":null,"is_member":true,"is_host":true}}
        """)
        #expect(view.viewer.isHost && view.viewer.isMember)
        #expect(view.viewer.playerRecordId == nil)
        #expect(view.session.originalHostUserId?.uuidString.lowercased() == host)
        #expect(view.session.currentPhaseData == .night(nightIndex: 0, activeRole: nil))
        #expect(view.session.nightHistory.first?.isResolved == true)
    }

    @Test func roundStateDecodesActionsAndDrafts() throws {
        let round = UUID().uuidString.lowercased()
        let player = UUID().uuidString.lowercased()
        let state = try decode(RoundState.self, """
        {"round_id":"\(round)","phase":"night","phase_index":0,"ready_to_advance":false,
         "actions":[{"id":"\(UUID().uuidString)","session_id":"\(UUID().uuidString)","round_id":"\(round)",
           "action_type":"inspector_check","phase_index":0,"actor_player_id":"\(player)",
           "target_player_id":"\(player)","action_data":{"inspector_result":"blocked"},"created_at":5}],
         "tentative":[{"actor_player_id":"\(player)","action_type":"mafia_target","phase_index":0,"updated_at":6}]}
        """)
        #expect(state.actions.first?.actionData?.inspectorResult == "blocked")
        #expect(state.tentative.first?.targetPlayerId == nil)

        let lobby = try decode(RoundState.self, """
        {"round_id":null,"phase":"lobby","phase_index":null,"ready_to_advance":false,"actions":[],"tentative":[]}
        """)
        #expect(lobby.roundId == nil && lobby.phaseIndex == nil)
    }

    @Test func playerProjectionDecodesIsMe() throws {
        let player = try decode(SessionPlayer.self, """
        {"id":"\(UUID().uuidString)","session_id":"\(UUID().uuidString)","player_id":"\(UUID().uuidString)",
         "player_name":"Bot 1","is_bot":true,"is_alive":true,"is_online":false,"is_ready":true,
         "last_heartbeat":1,"joined_at":1,"is_me":false}
        """)
        #expect(player.userId == nil && player.role == nil && !player.isMe)
    }

    @Test func outcomesDecodeNullableFields() throws {
        let night = try decode(NightOutcome.self, """
        {"night_index":0,"resulting_deaths":[],"next_phase":"morning","winner":null}
        """)
        #expect(night.winner == nil && night.nextPhase == "morning")
        let vote = try decode(VoteOutcome.self, """
        {"day_index":0,"eliminated_player_id":null,"next_phase":"game_over","winner":"citizen"}
        """)
        #expect(vote.winner == .citizen && vote.eliminatedPlayerId == nil)
    }
}

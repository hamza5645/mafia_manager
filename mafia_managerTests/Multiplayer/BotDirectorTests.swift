import Foundation
import Testing

@testable import mafia_manager

@MainActor
struct BotDirectorTests {
    private let decisions = BotDecisionService()

    private func nightPlans(_ players: [SessionPlayer], _ actions: [GameAction]) -> [BotPlan] {
        BotDirector.nightPlans(players: players, actions: actions, nightHistory: [], decisions: decisions)
    }

    private func role(of id: UUID?, in players: [SessionPlayer]) -> Role? {
        players.first { $0.playerId == id }?.role
    }

    // MARK: - Inspector (9+ players have two inspectors)

    @Test func botInspectorPicksItsOwnTargetWhenTheHumanInspectsIt() throws {
        let human = Fixture.seat(.inspector, bot: false)
        let botInspector = Fixture.seat(.inspector)
        let others = (0..<4).map { _ in Fixture.seat(.mafia) } + [Fixture.seat(.doctor), Fixture.seat(.citizen), Fixture.seat(.citizen)]
        let players = [human, botInspector] + others
        let actions = [Fixture.action(human, .inspectorCheck, target: botInspector)]

        for _ in 0..<50 { // Bot choices are random.
            let plan = try #require(nightPlans(players, actions).first { $0.botPlayerId == botInspector.playerId })
            #expect(plan.actionType == .inspectorCheck)
            let target = try #require(plan.target)
            #expect(target != botInspector.playerId, "The server rejects self-inspection forever")
            #expect(role(of: target, in: players) != .inspector)
        }
    }

    @Test func botInspectorFollowsAnAcceptableHumanTarget() {
        let human = Fixture.seat(.inspector, bot: false)
        let botInspector = Fixture.seat(.inspector)
        let suspect = Fixture.seat(.citizen)
        let players = [human, botInspector, suspect, Fixture.seat(.mafia)]
        let plans = nightPlans(players, [Fixture.action(human, .inspectorCheck, target: suspect)])
        #expect(plans.first { $0.botPlayerId == botInspector.playerId }?.target == suspect.playerId)
    }

    @Test func inspectorBotWithAnActionIsNeverResubmitted() {
        let botInspector = Fixture.seat(.inspector)
        let suspect = Fixture.seat(.citizen)
        let players = [botInspector, suspect, Fixture.seat(.mafia)]
        let plans = nightPlans(players, [Fixture.action(botInspector, .inspectorCheck, target: suspect)])
        #expect(!plans.contains { $0.botPlayerId == botInspector.playerId })
    }

    // MARK: - Mafia

    @Test func mafiaBotsFollowTheLatestHumanTarget() {
        let olderHuman = Fixture.seat(.mafia, bot: false)
        let newerHuman = Fixture.seat(.mafia, bot: false)
        let bot = Fixture.seat(.mafia)
        let first = Fixture.seat(.citizen)
        let second = Fixture.seat(.citizen)
        let players = [olderHuman, newerHuman, bot, first, second]
        let actions = [
            Fixture.action(newerHuman, .mafiaTarget, target: second, at: 20),
            Fixture.action(olderHuman, .mafiaTarget, target: first, at: 10),
        ]
        #expect(nightPlans(players, actions) == [BotPlan(botPlayerId: bot.playerId, actionType: .mafiaTarget, target: second.playerId)])
    }

    @Test func mafiaBotNeverFollowsOntoATeammate() throws {
        let human = Fixture.seat(.mafia, bot: false)
        let bot = Fixture.seat(.mafia)
        let teammate = Fixture.seat(.mafia)
        let players = [human, bot, teammate, Fixture.seat(.citizen), Fixture.seat(.doctor)]
        let actions = [Fixture.action(human, .mafiaTarget, target: teammate)]
        for _ in 0..<50 {
            let plan = try #require(nightPlans(players, actions).first { $0.botPlayerId == bot.playerId })
            let target = try #require(plan.target)
            #expect(role(of: target, in: players) != .mafia)
        }
    }

    @Test func botsWaitForTheirHumanTeammate() {
        let players = [Fixture.seat(.doctor, bot: false), Fixture.seat(.doctor), Fixture.seat(.citizen)]
        #expect(nightPlans(players, []).isEmpty)
    }

    @Test func mafiaBotsWithoutHumansShareOneTarget() throws {
        let bots = (0..<3).map { _ in Fixture.seat(.mafia) }
        let players = bots + (0..<4).map { _ in Fixture.seat(.citizen) }
        let plans = nightPlans(players, [])
        #expect(plans.count == 3)
        let target = try #require(plans.first?.target)
        #expect(plans.allSatisfy { $0.target == target })
        #expect(role(of: target, in: players) == .citizen)
    }

    @Test func remainingMafiaBotsReuseTheSubmittedBotTarget() {
        let submitted = Fixture.seat(.mafia)
        let pending = Fixture.seat(.mafia)
        let victim = Fixture.seat(.citizen)
        let players = [submitted, pending, victim, Fixture.seat(.citizen), Fixture.seat(.citizen)]
        let plans = nightPlans(players, [Fixture.action(submitted, .mafiaTarget, target: victim)])
        #expect(plans == [BotPlan(botPlayerId: pending.playerId, actionType: .mafiaTarget, target: victim.playerId)])
    }

    @Test func deadBotsAndCitizensDoNotAct() {
        let players = [Fixture.seat(.doctor, alive: false), Fixture.seat(.citizen), Fixture.seat(.citizen, bot: false)]
        #expect(nightPlans(players, []).isEmpty)
    }

    // MARK: - Voting

    @Test func everyLivingBotWithoutATargetedVoteVotes() {
        let abstained = Fixture.seat(.citizen)
        let voted = Fixture.seat(.mafia)
        let silent = Fixture.seat(.doctor)
        let dead = Fixture.seat(.citizen, alive: false)
        let human = Fixture.seat(.citizen, bot: false)
        let players = [abstained, voted, silent, dead, human]
        let actions = [
            Fixture.action(abstained, .vote, target: nil),
            Fixture.action(voted, .vote, target: human),
        ]
        let plans = BotDirector.votePlans(players: players, actions: actions, nightHistory: [], dayHistory: [], decisions: decisions)
        #expect(Set(plans.map(\.botPlayerId)) == [abstained.playerId, silent.playerId])
        #expect(plans.allSatisfy { $0.actionType == .vote && $0.target != nil })
    }

    @Test func canTargetMatchesServerValidation() {
        let inspector = Fixture.seat(.inspector)
        let mafia = Fixture.seat(.mafia)
        let citizen = Fixture.seat(.citizen)
        let dead = Fixture.seat(.citizen, alive: false)
        let alive = [inspector, mafia, citizen]
        #expect(BotDirector.canTarget(nil, actor: inspector, role: .inspector, alive: alive))
        #expect(BotDirector.canTarget(citizen.playerId, actor: inspector, role: .inspector, alive: alive))
        #expect(!BotDirector.canTarget(inspector.playerId, actor: inspector, role: .inspector, alive: alive))
        #expect(!BotDirector.canTarget(mafia.playerId, actor: mafia, role: .mafia, alive: alive))
        #expect(!BotDirector.canTarget(dead.playerId, actor: mafia, role: .mafia, alive: alive))
        let doctor = Fixture.seat(.doctor)
        #expect(BotDirector.canTarget(doctor.playerId, actor: doctor, role: .doctor, alive: alive + [doctor]))
    }
}

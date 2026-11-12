import { ConvexError } from 'convex/values';
import { expect, test } from 'vitest';
import { Doc } from '../../convex/_generated/dataModel';
import { E } from '../../convex/lib/errors';
import { evaluateWinners, roleDistribution, validateGameAction } from '../../convex/lib/rules';
import { NightType, Role } from './helpers';

// tests/fixtures/rules-parity.json holds the rules Swift duplicates: the role
// table, the target rules, the win conditions and the server messages. It is
// written from convex/lib/rules.ts and convex/lib/errors.ts; RulesParityTests
// and SoloRulesParityTests decode it. A normal run fails when the code drifts
// from the file. After a deliberate rule change, regenerate it with
// `npx vitest run tests/convex/rules-parity.test.ts -u` and run the Swift tests.

type Seat = Doc<'session_players'>;
const ROLES: Role[] = ['mafia', 'doctor', 'inspector', 'citizen'];
const ACTIONS: (NightType | 'vote')[] = ['mafia_target', 'doctor_protect', 'inspector_check', 'vote'];

const seat = (n: number, role: Role, alive = true, bot = true) =>
  ({ player_id: `p${n}`, role, is_alive: alive, is_bot: bot }) as Seat;

function accepts(action: NightType | 'vote', actor: Seat, target: Seat) {
  const session = {
    status: 'in_progress', is_game_over: false, current_phase: action === 'vote' ? 'voting' : 'night',
    current_phase_data: action === 'vote' ? { type: 'voting', dayIndex: 0 } : { type: 'night', nightIndex: 0 },
  } as Doc<'game_sessions'>;
  try {
    validateGameAction(session, [actor, target], {
      action_type: action, phase_index: 0, actor_player_id: actor.player_id, target_player_id: target.player_id,
    });
    return true;
  } catch (error) {
    if (error instanceof ConvexError) return false;
    throw error;
  }
}

function parity() {
  const role_counts = Array.from({ length: 16 }, (_, i) => ({ players: i + 4, ...roleDistribution(i + 4) }));
  const target_rules = ACTIONS.flatMap(action_type => ROLES.flatMap(actor_role => {
    const actor = seat(1, actor_role);
    const others = ROLES.flatMap(target_role => [true, false].map(target_alive =>
      ({ action_type, actor_role, target_role, target_alive, target_is_actor: false,
        allowed: accepts(action_type, actor, seat(2, target_role, target_alive)) })));
    return [{ action_type, actor_role, target_role: actor_role, target_alive: true, target_is_actor: true,
      allowed: accepts(action_type, actor, actor) }, ...others];
  }));
  // Survivors after the night or the vote; `all_bots: false` means at least one is human.
  const win_cases = [];
  for (const after of ['night', 'vote'] as const) {
    for (let mafia = 0; mafia <= 3; mafia++) {
      for (let non_mafia = 0; non_mafia <= 4; non_mafia++) {
        for (const all_bots of [false, true]) {
          if (all_bots && mafia + non_mafia === 0) continue;
          const alive = [...Array(mafia).fill('mafia'), ...Array(non_mafia).fill('citizen')]
            .map((role, i) => seat(i, role, true, all_bots || i > 0));
          const { over, winner } = evaluateWinners(alive);
          win_cases.push({ mafia, non_mafia, all_bots, after, over, winner: winner ?? null });
        }
      }
    }
  }
  return { role_counts, target_rules, win_cases, messages: { ...E } };
}

// One row per line, so a rule change reads as a small diff.
function format(fixture: Record<string, unknown>) {
  const body = Object.entries(fixture).map(([key, value]) => {
    const text = Array.isArray(value)
      ? `[\n${value.map(row => `    ${JSON.stringify(row)}`).join(',\n')}\n  ]`
      : JSON.stringify(value, null, 2).replace(/\n/g, '\n  ');
    return `  ${JSON.stringify(key)}: ${text}`;
  });
  return `{\n${body.join(',\n')}\n}\n`;
}

test('rules-parity.json matches the server rules and messages', async () => {
  const fixture = parity();
  expect(fixture.role_counts.map(row => row.players)).toEqual(Array.from({ length: 16 }, (_, i) => i + 4));
  // The table pins the PA-13 rule: parity is a mafia win after a night and after a vote.
  expect(fixture.win_cases).toContainEqual({ mafia: 1, non_mafia: 1, all_bots: false, after: 'night', over: true, winner: 'mafia' });
  expect(fixture.win_cases).toContainEqual({ mafia: 0, non_mafia: 0, all_bots: false, after: 'vote', over: true, winner: null });
  await expect(format(fixture)).toMatchFileSnapshot('../fixtures/rules-parity.json');
});

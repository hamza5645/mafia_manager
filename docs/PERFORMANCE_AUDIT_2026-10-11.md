# Performance & Reliability Audit — 2026-10-11

Scope: the whole repository at `070ac0a` (`main`) plus the untracked working-tree state: the iOS app (SwiftUI, Tuist), the Convex backend, tests, build configuration and tooling.
Mode: **report only**. As requested, nothing in the codebase was changed. This file is the only addition to the repo. The one other change: at your request after the audit, I deleted the 45 iCloud duplicate files (§5). Every experiment ran on throwaway copies outside the repo, on temporary simulators, and against the dev Convex deployment in read-only mode.

Updated the same day with a second measurement pass on the Xcode 27.0 release: Instruments, `leaks`, `heap`, `vmmap` and automated solo games (§3.8, PA-101–PA-103).

Finding IDs use the `PA-NN` prefix. Severity is Critical / High / Medium / Low. Each finding's evidence is labelled:

- **Measured:** I ran it and got a number.
- **Code-verified:** an independent verifier traced it in the source.
- **Inferred:** it follows from the code or docs but was not observed.

---

## 1. Executive summary

**Overall health is good where apps usually hurt.**

- Day-to-day builds are fast: 3–4 s incremental.
- 101 of 105 unit tests pass (4 skipped). 47/47 backend tests pass. The Convex TypeScript type-check is clean.
- Every Convex read is index-backed and projected per viewer for role privacy.
- Convex insights show no write conflicts and no read-limit warnings on dev or prod.
- On the client, decoding a full 19-player roster takes about 0.1 ms. Saving the solo game takes about 0.4 ms. Building the guest proof takes about 0.26 ms.
- The app's own startup code costs 64–69 ms of main-thread time per launch, and three-quarters of that is the sound warm-up (PA-55).
  - On the simulator, launch time is dominated by the system loader. AuthenticationServices, pulled in by Clerk, adds about 1,000 system libraries and 1–2 s there (PA-101). The impact on a device was not measured.
- Solo play uses about 4% main-thread CPU. Memory stays at 44–75 MB with no growth across games, apart from a brief spike when leaving the Game Over screen (PA-103). `leaks` finds no app leaks (§3.8).

None of these is a bottleneck. **No Critical issues were found.**

**What matters, in priority order:**

1. **The working copy could not build (PA-03, measured).** iCloud had created 45 byte-identical `* 2.*` conflict copies in the checkout. 21 of them are Swift files that Tuist's globs pick up. `tuist generate` followed by a build failed with 316 error lines. The root cause is that the repo lives in iCloud-synced `~/Documents` (PA-17), and it will keep recurring after large git operations.
   - Done after the audit, at your request: the copies were deleted.
   - Still to do: move the clone out of iCloud. Before the next `tuist generate`, rebuild the stale `Tuist/.build` cache (PA-102).
2. **Heartbeats dominate backend cost and grow quadratically with players (PA-01, code-verified plus measured payloads).** Every 5 s heartbeat writes the seat row. Two of the three per-viewer subscriptions read that same row range, so each heartbeat re-runs both queries for every member and pushes the full roster to every phone, even when nothing in the game changes. Per room, while idle:

   | Humans in the room | Query re-runs per 5 s | Data pushed per 5 s | Function calls per hour (incl. heartbeat mutations) |
   |---|---|---|---|
   | 8 | 136 | 193 KB | ≈104k |
   | 19 | 741 | 2.6 MB | ≈547k |

   Convex's own limits doc counts subscription updates as function calls. The Free plan includes 1M calls and 1 GB of database I/O per month. One 8-human room is estimated to use that database I/O allowance in roughly 1.5–2 game-hours.
   - The phone-side cost is small: I measured 1.4–2.0 ms of re-rendering per redundant push.
   - Fix: move presence into its own table.
3. **One silently disconnected player stalls the game forever (PA-02, code-verified).** A force-quit or a dead battery is enough. Night and vote readiness wait for every alive human. There is no timeout, no in-game kick and no "waiting for…" list. The room code is not shown during a game, so the missing player cannot easily rejoin.
   - Recommended first step, client-only: a host "Waiting for…" list with a Remove action, plus the room code shown during the game.
   - This is the most likely way a real multiplayer session fails.
4. **Host hand-off and connection-state reliability (PA-05–PA-09).**
   - The host loses host controls after about 10–20 s of backgrounding or auto-lock, and there is no way to reclaim them.
   - Real network loss is invisible: no reconnect banner, and mutations have no timeout.
   - One-shot queries can spin forever while offline.
   - Cancelling during create/join leaves an invisible live session.
5. **Game-rule correctness (PA-12–PA-14, code-verified).**
   - Bots can outvote a human Mafia majority.
   - Solo and multiplayer use different win conditions, and the tests pin opposite rules.
   - In solo games where every Mafia is a bot, the "close your eyes" gate is skipped and the screen shows that the Mafia are bots.
6. **Cheap measured wins.**
   - Removing the unused `ClerkKitUI` dependency (PA-18): clean builds 45–54% faster, IPA 4.6% smaller.
   - Locking iPhone to portrait (PA-15): in landscape the vote list renders 0 pt tall (measured), and several core screens push their only forward button off-screen.

**Count:** 103 findings: 0 Critical, 3 High, 16 Medium, 84 Low. 99 came from a 123-agent static audit in which every finding was checked against the code by an independent verifier (none refuted; 62 were corrected). One was added from my own build measurements, and three (PA-101–PA-103) came from the second measurement pass. My measurements changed three grades:
- PA-03 raised to High (build failure measured).
- PA-18 raised to Medium (build savings measured).
- PA-75 lowered from High to Low (rendering disproved the "lists collapse in portrait" claim).

**Implemented improvements:** no code changes, by request. At your request after the audit, I deleted the iCloud duplicate files (PA-03). Section 6 is the prioritized roadmap.

---

## 2. Scope, method and coverage

**Static audit.**
- 11 domain auditors:
  - Convex read path; Convex write path; Convex accounts/stats.
  - Multiplayer client; multiplayer views; solo views; solo core logic.
  - Startup/auth/settings; build/dependencies/tooling.
  - Concurrency/reliability; test suite.
- A completeness critic, which spawned 5 gap investigations:
  - third-party runtime behaviour behind the heartbeat finding;
  - landscape and iPad layout;
  - dev-data claims;
  - multiplayer interaction latency;
  - client/server rule parity.
- Together they read **302 distinct files**.
- 170 raw findings were de-duplicated to 99.
- Every finding then went to an independent **code-truth verifier**, and the six High findings also went to an **impact-realism verifier**. Results: 37 confirmed, 62 partially confirmed (claims corrected), 0 refuted.
- Verifier corrections override the original wording throughout this report.

**Third-party sources** were read at the pinned versions, from the SwiftPM cache or public repositories:
- convex-swift 0.8.1, the convex-mobile Rust core, convex-rs 0.10.3;
- convex-backend (`crates/sync`, cache, keybroker) and its `limits.mdx` docs;
- clerk-ios 1.1.1.

**Measurements (mine):**
- Environment: Xcode 27.0 beta (27A5194q) on an Apple-silicon Mac, on throwaway copies:
  - `git archive HEAD`;
  - an rsync of the working tree;
  - HEAD without ClerkKitUI;
  - a bare SwiftUI control app.
- Runs used a temporary iPhone 17 / iOS 27.0 simulator.
- Release-configuration runs pointed at the **dev** Convex/Clerk deployment through build-setting overrides.
- Measured: clean and incremental builds, type-check hot spots, Release size and link map, unit and backend tests, cold launch (`XCTApplicationLaunchMetric`), first-screen memory and threads, decode/persistence/guest-proof microbenchmarks, a SwiftUI re-render bench, rendered layout probes (portrait and landscape), payload sizes via `convex-test`, network RTT, and Convex insights, function specs and table counts.
- **Second pass**, the same day on the Xcode 27.0 release (27A266a), covered these; see §3.8:
  - Instruments Time Profiler, App Launch and Core Animation Commits;
  - `leaks`, `heap`, `vmmap` and `footprint`;
  - library-load counts;
  - automated solo games driven through accessibility.

**Not covered:**
- Physical devices. Every runtime number is from the simulator.
- Instruments on a device. On the simulator, Time Profiler, App Launch and Core Animation Commits work. SwiftUI, Hitches and Network produced no data there, and Allocations data cannot be exported from the command line (§3.8).
- Multiplayer screens at runtime. The automated games covered solo play only, so nothing was written to the dev backend.
- Real multi-device sessions over a real network.
- Production traffic: prod tables are near-empty.
- Energy measurements.
- MetricKit / App Store data.
- iPad and accessibility text sizes, which were not rendered.

See section 8 for limitations.

**Safety:**
- No writes to the dev or prod deployment: read-only queries, insights and function specs only.
- Your two existing simulators were not touched.
- The repo's working tree was not modified, apart from adding this file.

---

## 3. Measured baseline

All numbers are measured on the simulator unless marked otherwise. The machine was also running audit agents, so wall-clock numbers are noisy; CPU-seconds and A/B ratios are more reliable.

### 3.1 Build and toolchain

| Metric | Result |
|---|---|
| `tuist install` / `tuist generate` | 7.0 s / 2.5 s |
| Clean Debug build (HEAD) | 55.3 s wall, 261 s CPU, peak RSS 858 MB; SwiftCompile 243 s over 92 tasks |
| Clean Debug without ClerkKitUI | 30.7 s wall, 127 s CPU. A second pair under heavier load: 120.1 → 55.0 s wall, 469 → 191 s CPU |
| Incremental: no-op / leaf view / `DesignSystem` / `GameStore` edit | 2.9 s / 4.0 s / 3.5 s / 3.6 s |
| Compile share by module (relative) | clerk-ios ≈52 s, app Features ≈23 s, Nuke 6.4 s, app Core 4.5 s, PhoneNumberKit 4.1 s, convex-swift 1.2 s |
| Slowest type-checked bodies | `SetupView.body` 1080 ms, `LoadCustomRoleConfigSheet.body` 438 ms, `SettingsView.body` 436 ms, `JoinGameView.body` 426 ms, `SignupView.body` 354 ms, `lobbyContent` 316 ms |
| Warnings in a clean Debug build | 27 (PA-91) |
| Working-tree build after `tuist generate` | **Fails: 316 error lines** from the ` 2.swift` duplicates (PA-03) |

### 3.2 Tests and type-check

| Suite | Result |
|---|---|
| Unit tests (`xcodebuild test`, app-hosted) | 105 tests (43 XCTest + 62 Swift Testing): **101 passed, 4 skipped, 0 failed**. Execution time 0.43 s; total run ≈100–108 s, almost all build, install and host-app boot (PA-92) |
| Backend (`vitest run`) | **47/47 passed**, 1.03 s (2.5 s wall) |
| `tsc --noEmit -p convex/tsconfig.json` | Pass, 0.45 s |

### 3.3 Launch, memory and idle cost

| Metric | App | Bare SwiftUI control |
|---|---|---|
| Cold launch to responsive (Release, 8 runs) | 2.752 s mean, RSD 0.98% | 2.469 s mean, 2.33 s median, RSD 12.7% |
| Physical footprint on the first screen | 48 MB, settling to 35 MB | 17 MB |
| Threads on the first screen | 15, including 8 `tokio-runtime-worker` (Convex Rust client created eagerly) and 2 audio threads (sound warm-up) | 4 |
| Idle CPU on the Intro screen | 0.3% (max 0.4%) | n/a |

These are pass-1 numbers from the Xcode 27 beta. The second pass (§3.8) breaks the launch down: about 65 ms is app code, and most of the rest is the system loader (PA-101).

### 3.4 Runtime micro-costs (optimized build)

| Operation | Cost |
|---|---|
| Decode `[SessionPlayer]`: 8 / 19 seats (3.0 KB / 7.4 KB) | 42 µs / 104 µs |
| `apply(players:)` / derived-property recompute | 0.97 µs / 2.47 µs |
| `objectWillChange` emissions for 10 identical snapshots | **10** (no equality guard; PA-10, PA-34) |
| Guest proof per request (Keychain read + SHA-256, MainActor) | 259 µs |
| Solo `GameState` (19 players): encode compact / pretty / `saveImmediately` / load | 47.7 µs / 57 µs / 415 µs / 128 µs |

### 3.5 Multiplayer fan-out and re-render cost

Payload sizes come from running the real view functions in `convex-test` and measuring raw JSON:
- `getPlayers` ≈ 380 B per seat: 1515 B for 4 seats, 3017 B for 8, 4554 B for 12, 7241 B for 19.
- `getRoundState` 105–136 B early in a round.
- `getSessionView` 1–2 KB for the host, growing about 0.57 KB per night.

Idle cost per room per 5 s, when every human heartbeats once (each push is a full roster):

| Humans | Query re-runs | `getPlayers` pushes | Bytes pushed | Per-phone download (continuous) |
|---|---|---|---|---|
| 4 | 36 | 16 | 24 KB | ≈1.2 KB/s |
| 8 | 136 | 64 | 193 KB | ≈4.8 KB/s (≈17 MB/h) |
| 12 | 300 | 144 | 656 KB | ≈11 KB/s |
| 19 | 741 | 361 | 2.6 MB | ≈27 KB/s (≈99 MB/h) |

Re-render cost of a redundant push. Measured in an optimized build: 12 players, hosted `NavigationStack { MultiplayerLobbyView() }`, 100 iterations, against an idle baseline of about 1.3 ms per iteration.

| Phase | Identical push | Heartbeat-only push | Bodies re-evaluated per push |
|---|---|---|---|
| Lobby | 2.63 ms | 2.87 ms | Container only; `PlayerRow` is not re-evaluated |
| Night | 3.38 ms | 3.03 ms | Container + `MultiplayerNightView` + 11 `TargetGridCell` |
| Voting | 3.31 ms | 3.06 ms | Container + voting view + 4 `VoteTargetButton` |

So the extra main-thread cost is about 1.4–2.0 ms per redundant push. With 12 humans that is about 5 ms per second, which is negligible for frame rate. The heartbeat problem is about network, function calls, database bandwidth and battery, not jank.

### 3.6 Rendered layout probes (iPhone 17, 402×874 pt)

| Screen | Portrait | Landscape (874×402) |
|---|---|---|
| MP voting, 12 players, non-host | List 281 pt for 828 pt of content (≈3.7 rows); host 346 pt | **List 0 pt** |
| MP night, Mafia with a teammate, 8 players | Grid 289 pt for 227 pt of content (all targets visible) | not probed |
| MP role reveal | n/a | Content overflows: avatar clipped at the top, confirm control below the screen edge |

### 3.7 Network, backend and binary

**Network and backend:**
- ICMP RTT to Convex eu-west-1: 42 ms.
- Cold HTTPS `health:check`: p50 282 ms (205–385 ms), 216 ms once connected.
- Older dev logs show server execution p50 of 10–30 ms for mutations and 10–17 ms for queries.

**Convex insights (dev and prod, last 72 h):**
- 0 OCC conflicts, 0 read-limit warnings. Traffic is low.
- No deployed function declares a `returns` validator.

**Dev table counts:**

| Table | Rows |
|---|---|
| `users` | 330 |
| `game_sessions` | 224 (207 cancelled, 9 completed, 8 waiting) |
| `session_players` | 61 |
| `game_actions` | 50 |
| `player_stats` | 58 |

**Release binary (generic iOS):**
- Executable: 21.5 MB unstripped, 11.2 MB stripped.
- Link-map attribution: ConvexMobile including its Rust core 5.02 MB (51%), app code 2.62 MB (27%), ClerkKit 1.95 MB (20%).
- `.app` 22.9 MB; zipped IPA 5.27 MB.
- The four `.wav` sound files are actually AAC in an M4A container (PA-63).

### 3.8 Second pass: Instruments, leaks and memory (Xcode 27.0 release)

After you installed Xcode 27.0 (27A266a), xctrace 27.0 and the iOS 27.0 simulator runtime, I repeated the runtime work with the tools that had hung on the beta.

**Setup.**
- A fresh `git archive` of `070ac0a`, built in Release and Debug for a new temporary iPhone 17 / iOS 27.0 simulator, pointed at the dev backend.
- A script drove complete solo games through AXe, the accessibility automation tool bundled with XcodeBuildMCP.
  - Each game had 1 human and 7 bots.
  - The script went through role reveal, night actions, morning summary, bot votes, the human vote and game over, then tapped "Play again".
  - It read each screen through accessibility and tapped the next step, so it adds some accessibility work in the app. The CPU numbers below are therefore upper bounds.
- Launches were profiled by starting the app suspended (`simctl launch --wait-for-debugger`), attaching Instruments, then resuming it. That records a real foreground launch.
  - `xctrace --launch` starts the app without bringing it to the foreground, so `onAppear` never runs. I used it only for the pre-`main` loader comparisons.
- Signed out, the solo stats sync returns early (`GameStore.swift:682-684`), so these runs wrote nothing to Convex.

**Tools and what worked on the simulator:**

| Tool | Result on Xcode 27.0 + iOS 27.0 simulator | Used for |
|---|---|---|
| Time Profiler (`xctrace record`) | **Works.** A 10 s launch trace is about 3 MB | Launch attribution, gameplay CPU |
| App Launch template | **Works**, but heavy: a 15 s recording wrote about 2 GB of raw kernel trace and filled the disk once; 6 s recordings are 70–120 MB | Loader phase timing |
| Core Animation Commits instrument | **Works** | Commit durations during play |
| Allocations template | Records, but `xctrace export` exposes no allocation tables; it needs the Instruments app | Not usable from the command line |
| SwiftUI instrument | Records, but produced no SwiftUI data in attach or launch mode | Not usable on the simulator |
| SwiftUI and Animation Hitches templates | Fail: "Hitches is not supported on this platform" | Device only |
| Network template | Records, but every network table is empty | Device only |
| `leaks` (Debug build, `MallocStackLogging=1`) | **Works.** On Release builds it only reports counts, because they are not debuggable | Leak check |
| `heap`, `vmmap --summary`, `footprint` | **Work** | Memory composition and growth |
| `malloc_history -highWaterMark` | Refused: the simulator stayed in lite logging mode even with `MallocStackLoggingNoCompact=1` | Not usable |
| `DYLD_PRINT_LIBRARIES` via `simctl launch` | **Works** | Counting libraries loaded at launch |

**Launch (Release).** The loader rows compare the app with an empty SwiftUI app:

| Measure | App | Empty SwiftUI app | Empty app + `import AuthenticationServices` |
|---|---|---|---|
| System images loaded at launch | **1,603** | 596 | 1,597 |
| Loader CPU per launch (`dyld_sim` self time, 3–4 runs) | 1,325–1,688 ms | 448–596 ms | 1,535–1,698 ms |
| Loader wall time (`Launch Executable` interval) | 1,867–2,930 ms | 698–1,049 ms | 1,949–2,753 ms |
| Static initializers (all images) | 52.6 ms | 51.2 ms | n/a |

App code on the main thread, from three foreground launches (Time Profiler, 1 ms sampling):

| Work | Main-thread time per launch |
|---|---|
| **All app code** | **64–69 ms** |
| `SoundManager.warmUp()`, from the root view's `onAppear` (PA-55) | **48–54 ms**, of which `AVAudioPlayer.init(contentsOf:)` is 17–20 ms |
| `GameStore.init()` | 7–8 ms |
| Clerk `configure` and `refreshClient` | 7–8 ms |
| `ConvexService` init (PA-55's eager Convex client) | 6–7 ms |

So the app's own startup is cheap, and three-quarters of it is the sound warm-up. On the simulator, the pre-`main` loader dominates. AuthenticationServices explains the whole gap against an empty app (PA-101).

**Gameplay CPU (Release, Time Profiler attached during a game).**
- Main thread: 4.0% of one core over 28 s, at most 80 ms in any one second.
- App code in that time:
  - `Persistence.save`: 17 ms.
  - `SoundManager.play`: about 12 ms.
  - The rest is SwiftUI, UIKit and Core Animation, plus accessibility bookkeeping for the driver.
- About 0.5 s of loader work in the first 3 s came from UIKit loading its accessibility bundles when the driver connected. That is an artifact of the automation, not the app.

**Frame commits (Core Animation Commits, launch plus part of a game).**
- 274 commits: median 0.09 ms, p95 4.1 ms.
- Only 3 took longer than one frame:
  - the first frame at launch, 276 ms;
  - one 19 ms commit;
  - the Game Over screen appearing, 95 ms (PA-103).

**Memory (Release, no malloc logging, fresh install).**

| Point | Footprint | Lifetime peak | Threads |
|---|---|---|---|
| Intro screen, 8 s after launch | 44–52 MB | 44–53 MB | 16–20 |
| After 1 game | 64 MB | 70–72 MB | 17 |
| After 5 games | 64–75 MB | 171 MB (Play-again spike, PA-103) | 19 |
| An earlier, longer run: several games of 8–18 players (exact count not reliable) | 57–60 MB | 102 MB | 17 |

- There is no growth trend across games.
- Composition after 5 games (`vmmap`): `MALLOC_SMALL` 28.6 MB dirty, Core Animation 6.8 MB, `__DATA` 6.6 MB.
- The largest `heap` classes are untyped buffers (11.4 MB), Swift metadata (2.8 MB), Objective-C method caches (2.5 MB) and CoreSVG symbol data (about 1.5 MB). Nothing app-specific is large.
- The Debug build with malloc logging reaches 130–140 MB, but 64 MB of that is the logging's own "Performance tool data".

**Leaks (Debug build, `MallocStackLogging=1`).**
- At the intro screen: 3 leaks, 128 bytes.
- After 3 complete games: 24 leaks, 1,136 bytes.
- Every one is rooted in `map_images_nolock`, the Objective-C runtime registering newly loaded system images. None involves app code, so **no app leaks were found**.

---

## 4. Findings

### 4.1 High severity

#### PA-01 · Heartbeats rewrite the roster rows that two subscriptions read, so presence re-runs queries quadratically and pushes full rosters every 5 s

**Severity:** High · **Status:** Recommended · **Evidence:** Code-verified; payloads and render cost measured; billing basis from Convex docs · **Effort:** M

**Location:** `convex/sessions.ts:167-178`, `convex/lib/guards.ts:16-22`, `convex/views.ts:13-71`, `Core/Multiplayer/Store/MultiplayerGameStore+Connection.swift:89-108`

**Problem.** Every human calls `sessions:heartbeat` every 5 s. It patches that player's own `session_players` row (`last_heartbeat`, plus an `is_online: true` that never changes). Two queries read that table:
- `views:getPlayers` reads the whole roster through `listSeats`, a full `by_session` range.
- `views:getRoundState` reads it too, through `loadMember` → `listSeats`.

So each heartbeat invalidates both queries for every member, plus the sender's own `getSessionView`. That is 2H+1 re-executions per heartbeat and H·(2H+1) per 5 s window.
- Convex suppresses unchanged results by hash, so `getRoundState` and `getSessionView` are not re-sent.
- `getPlayers` projects `last_heartbeat` for every row, so its result always changes and the full roster is pushed to every phone.
- The convex-rs client then re-broadcasts all three subscription values on every transition. Each push therefore triggers three unconditional `@Published` assignments plus a host automation pass on every device.
- Query results cannot be shared between viewers, because each viewer's projection is different.

**Evidence.**
- Code: `sessions.ts:175` `await ctx.db.patch(seat._id, { last_heartbeat: nowAppleEpochSeconds(), is_online: true })`; `guards.ts:17-20` `.withIndex("by_session", …).collect()`; `views.ts:18` `const seats = await listSeats(ctx, session.id)`; `projections.ts:99-101` emits `is_online` and `last_heartbeat`; `MultiplayerGameStore.swift:136-142` assigns `players` unconditionally.
- Server dedupe, and Authenticate re-running every query, were confirmed in convex-backend `sync/state.rs:454-462` and `worker.rs:955-966`. The client re-broadcast was confirmed in convex-rs `base_client/mod.rs:655-665`.
- Measured: the payload and fan-out tables in §3.5, and 1.4–2.0 ms of render cost per redundant push.

**Impact.** Estimated function calls per room-hour, counting query re-runs plus heartbeat mutations:

| Humans | Calls per room-hour |
|---|---|
| 4 | ≈29k |
| 8 | ≈104k |
| 12 | ≈225k |
| 19 | ≈547k |

That is roughly 15–20× the traffic of real game events. Database I/O for an 8-human room is estimated at about 0.55–0.65 GB per hour.
- Convex's limits doc counts subscription updates as function calls. Re-runs after an invalidation miss the query cache, so they also count as database I/O.
- The Free plan (1M calls and 1 GB per month, hard caps) would cover only about 1.5–2 hours of one 8-human room before writes may fail. Starter adds overage billing at $2.20 per 1M calls and $0.22 per GB.
- Each phone downloads 17–99 MB per hour while idle (8–19 humans), which matters on cellular.
- Client CPU stays under 1% of one core (measured).
- Write conflicts are possible in theory, because gameplay mutations also read the roster, but none were observed (0 OCC in insights).

The billing figures are modeled from the code and Convex's docs. They are not usage-dashboard measurements.

**Solution.** Move presence out of `session_players`:
1. Add a `session_presence {session_id, user_id, last_heartbeat}` table with index `by_session_user`. `sessions:heartbeat` and the `joinSession` re-entry write only that row.
2. Read presence server-side in `claimHost` and in `nextHostAfterDeath`/`transferHostAfterDeath`, inside the same transactions as today. This keeps record-then-resolve atomic.
3. Add a tiny `views:getHostPresence` (session doc plus one presence row) for the client's host-offline check. Its invalidation cost is about H small re-runs per 5 s, instead of H·(2H+1) heavy ones.
4. Remove `last_heartbeat` and `is_online` from `playerForViewer`.

Also add client-side dedupe, because own-mutation transitions still re-yield all three values:
- Make the snapshot models `Equatable` and skip assignments that are equal.
- Stop writing `isHostOffline` when it has not changed.

Rollout: removing the fields breaks the current build's non-optional decode. Emitting a constant `last_heartbeat` makes old clients think the host is offline. `apiContractVersion` is not checked at runtime (PA-30). So ship the backend and app in lockstep, which is easy now because no build has shipped yet. Otherwise, make the Swift fields optional one release ahead.

**Risk.** This is a contract change between app and backend (see Rollout above). The host-claim and transfer tests that patch `seat.last_heartbeat` (`tests/convex/sessions.test.ts`, `night.test.ts`) must move to presence.

#### PA-02 · A silently disconnected player stalls the night or vote forever: no timeout, no in-game removal, no "waiting for" view

**Severity:** High · **Status:** Recommended · **Evidence:** Code-verified; the frequency of the trigger is inferred · **Effort:** M

**Location:** `convex/lib/rules.ts:77-101`, `convex/night.ts:38`, `convex/voting.ts:38`, `Features/Multiplayer/Flow/MultiplayerLobbyView.swift:126-196`

**Problem.** What readiness waits for:
- Night readiness requires every alive human with an active role (Mafia, Doctor, Inspector) to submit.
- Voting readiness requires every alive human to vote.
- Bots of a role also wait for that role's human to act.

The server rejects `recordNightActions`/`closeVoting` until readiness holds. Failover exists only for the host. When any other required player's app process ends, the round can never resolve. Causes include a force-quit, iOS killing the suspended app, a dead battery, or simply walking away without tapping Leave. The ways out are limited:
- The kick UI exists only in the lobby.
- `is_online` is never set to false (PA-22).
- No screen shows whom the round is waiting for.
- The room code is shown only in the lobby, so the missing player cannot easily rejoin even though `joinSession` would restore their seat.

Role reveal can also stall on the client, because "Start Night" waits for every human to be ready. The server does not require this.

**Evidence.**
- `rules.ts:80-91`: `alive.every(...)` over actions.
- `rules.ts:98-100`: `.every((p) => p.is_bot ? votedWithTarget.has(...) : voted.has(...))`.
- `night.ts:38`: `if (!nightActionsReady(...)) fail(E.NIGHT_INCOMPLETE)`.
- `voting.ts:38`: `fail(E.VOTES_INCOMPLETE)`.
- Kick UI only in `lobbyContent`: `MultiplayerLobbyView.swift:194`.
- Room code only in `lobbyContent`: `MultiplayerLobbyView.swift:126-152`.
- `sessions:removePlayer` already works in any phase: `sessions.ts:141-150`. Kicked actors are covered by `night.test.ts:213`.

**Impact.** A stall needs all three of these:
- an alive human whose input is required (every alive human at a vote; about 40–70% of seats at night);
- that player's app ending;
- no rejoin.

When it happens, the whole table is stuck. The host's only escape is End Game, which loses the game for everyone. Brief backgrounding or network loss recovers on its own; host loss is handled by failover. With 5–19 people over a 30–60 minute session, a dead battery or force-quit is plausible. This is the most likely way a real session fails.

**Solution.** Client-only first steps, all supported by today's server:
- Add a host-only "Waiting for…" list to the role reveal, night and voting screens. Build it from the action rows the host already receives plus heartbeat age, and offer **Remove** (existing `sessions:removePlayer`) behind a confirmation.
- Let the host start the night before everyone has confirmed their role, behind a confirmation.
- Show the room code during the game, for example in the toolbar menu.

Do **not** treat stale heartbeats as automatic abstention inside `nightActionsReady`/`votesReady`, for three reasons:
- Heartbeats stop whenever a phone auto-locks or is backgrounded (PA-05, PA-06), so a thinking player would lose their turn.
- Readiness flipping to true triggers the host's auto-finish.
- When every Mafia row has no target, `majorityTarget` falls back to the first valid target (`rules.ts:110`), usually the host. Recording target-less "abstention" rows would silently kill them.

If automatic handling is wanted later, add explicit server-side abstention for the departed seat. It must exclude that seat's role from the fallback, and it needs vitest cases for an absent Mafia and an absent voter.

**Risk.** A host could remove someone who is only slow. The confirmation and the visible heartbeat age mitigate this. A removed player who returns can re-enter by code: re-entry restores the seat (`sessions.ts:101-109`).

#### PA-03 · iCloud conflict copies (`* 2.swift`) are matched by Tuist's source globs, so the working copy no longer builds

**Severity:** High (auditors: High; verified: Medium; raised by me because the build break was measured, is certain on this machine, and recurs) · **Status:** Partially implemented (copies deleted on request after the audit; moving out of iCloud still pending) · **Evidence:** Measured · **Effort:** S

**Location:** `Project.swift:47-52`, `Project.swift:84-86`, `Core/Multiplayer/Store/BotDirector 2.swift`, `Vendor/clerk-convex-swift/Sources/ClerkKitConvex/ClerkConvexAuthProvider 2.swift`

**Problem.** The checkout contains 45 untracked conflict copies, all byte-identical to their originals:
- 21 are Swift files inside the globbed source trees `Core/**`, `Features/**`, `Vendor/clerk-convex-swift/Sources/ClerkKitConvex/**` and `mafia_managerTests/**`.
- The rest are in `convex/`, `tests/`, `docs/`, `Configuration/`, `scripts/` and `Vendor/`.
- Plus `vitest.config 2.ts`, `convex/tsconfig 2.json`, and empty `docs 2/` and skill directories.

Tuist adds every matched file to the project, so every type is declared twice. File creation times show that 39 of the 45 copies were created at 23:36:21 on 2026-10-10. That is the same second as the `merge integration: Fast-forward` in `git reflog`, which rewrote 206 files inside the iCloud-synced folder (PA-17). The other 6 copies date from earlier events (three on 15 May, and one each on 10 July, 8 October and 9 October), so this has already happened several times. `.git/index 2` exists too, so git internals are exposed as well.

**Evidence.** Measured on an rsync copy of the working tree:
- `tuist generate` added 84 ` 2.swift` references to the project.
- The Debug build failed with 316 error lines, such as "'RoundState' is ambiguous for type lookup" and "invalid redeclaration".
- The same steps on pristine HEAD succeed.

`cmp` confirms all 45 copies are identical. The generated project is currently absent: the `git pull` at 00:42:47 on 2026-10-11 deleted the 11 previously tracked `mafia_manager.xcodeproj` and `.xcworkspace` files, and `mafia_manager.xcodeproj/` now has no `project.pbxproj`. The next `tuist generate`, which is now mandatory, will therefore hit this. The `convex/* 2.ts` copies are skipped by Convex's bundler, which ignores paths containing spaces. They are also outside vitest's include pattern, so they are not deployed or run. Neither of those two behaviours was verified by me.

**Impact.** Every build, test run and Release validation on this working copy fails until the files are deleted. That includes agent sessions in worktrees under `.claude/worktrees/`, which live in the same synced folder. It will happen again after the next large git operation. A quieter failure is also possible: if an original is later renamed or deleted, its stale ` 2` copy compiles silently, and the local build then differs from git. There is no user, runtime or production impact.

**Solution.**
1. Pause iCloud sync, or move the repo first (step 3). Otherwise iCloud can race the deletes.
2. Delete only the copies, never with `git clean`. For example:
   - `git ls-files --others --exclude-standard -z | grep -z ' [0-9]\(\.[^/]*\)\{0,1\}$'`, then `cmp -s` each file against its original and `rm` on a match.
   - `rmdir` the empty ` 2` directories.
   - Remove `.git/index 2`.
3. Re-clone outside iCloud, e.g. `~/Developer/mafia_manager` (PA-17).
4. Optional defence: Tuist glob exclusions such as `.glob("Core/**", excluding: ["Core/**/* [0-9].swift"])`, plus a matching `exclude` in `convex/tsconfig.json`.

**Risk.** Very low for the deletion: the files are untracked byte-identical copies. The exclusion glob would hide a real file deliberately named `Foo 2.swift`, a naming pattern this codebase does not use.

**Update after the audit.** At your request I deleted the 45 copies, each compared byte for byte with its original first, plus the 3 empty ` 2` folders and `.git/index 2`. Afterwards `git status` shows no ` 2` files and `git fsck` passes. A copy of the cleaned checkout generates with 0 duplicate references and builds with 0 errors once the stale `Tuist/.build` cache is rebuilt (PA-102). The underlying iCloud cause (PA-17) remains.

### 4.2 Medium severity

#### PA-04 · Game-end stats sync runs per player, is not idempotent, is tied to the view and is never retried

**Severity:** Medium (auditor: High; verified: Medium) · **Status:** Recommended · **Evidence:** Code-verified; sync duration is an estimate from measured RTT · **Effort:** M

**Location:** `Core/Gameplay/Store/GameStore.swift:681-727`, `Features/GameOver/GameOverView.swift:37-43`, `Core/Backend/DatabaseService.swift:32-49`, `convex/stats.ts:120-159`

**Problem.** `GameOverView`'s `.task` calls `syncPlayerStatsToCloud()`. It awaits one `stats:upsertPlayerStat` per player (up to 19) in turn and swallows every error. The mutation adds to counters and is documented as not idempotent. The only record that the sync ran is a view-scoped `@State hasSynced`. `GameState` has no game id or sync status, and nothing retries.

**Evidence.** Code-verified:
- an auth guard that returns early when not signed in (GameStore.swift:682-684);
- the empty `catch` (:722-725);
- `hasSynced = true`, set even when the guard skipped the sync (GameOverView.swift:41);
- "Not idempotent: a retry after a lost response counts the game twice" (DatabaseService.swift:32-33).

**Impact.** Online, every row is recorded and the loop runs in the background. Estimate from the measured 42 ms RTT and 10–30 ms server time: 55–75 ms per mutation, about 1–1.4 s for 19 players. Verified loss paths:
- a game that ends before auth is restored (offline launch, failed restore) is skipped for good;
- an app kill mid-loop drops the remaining players;
- a name within 50 graphemes but over 50 UTF-16 units is rejected by the server's `cleanText`.

Loss on Play Again or a network blip depends on convex-swift behaviour (inferred). Double counting is latent, not active. The result is silent, unrepairable drift in casual counters.

**Solution.** Add an additive `stats:recordGame({ game_id, results })` mutation. It checks a `recorded_games` table (index `by_user_game`) and upserts all rows in one transaction. At game end, write `{game_id, owner, results}` to a small persisted outbox, not to `GameState`, which `resetAll()` wipes. Flush the outbox from a store-owned task on enqueue, on auth change and on `.appDidBecomeActive`, and remove an entry only after the server acknowledges it. Delete `hasSynced`. Skip invalid rows rather than rejecting the whole batch.

**Risk.** `mergeGuestIntoAccount` must re-key `recorded_games`, or a retry after the merge double counts. Clear the outbox on sign-out. Any new `GameState` field must be optional, or old saves fail to decode.

#### PA-05 · Treating `.inactive` as background pauses the heartbeat and re-authenticates on every glance

**Severity:** Medium · **Status:** Recommended · **Evidence:** Code-verified; the per-blip Convex round trip is inferred · **Effort:** S

**Location:** `App/mafia_managerApp.swift:36-51`, `Core/Multiplayer/Store/MultiplayerGameStore+Connection.swift:72-85`, `Core/Auth/Store/AuthStore.swift:124-135`, `Core/Gameplay/Services/Persistence.swift:59-64`

**Problem.** The `scenePhase` handler treats `.inactive` like `.background`. But `.inactive` fires while the app is still on screen: Control Center, Notification Center, the app switcher, Siri and system alerts. Each blip saves the game, clears the audio-session flag and posts `appWillEnterBackground`, which cancels the multiplayer heartbeat. On return, AuthStore's foreground observer and the store's `handleAppResume` both call `ensureValidSession()`, and nothing stops the two calls from running at once.

**Evidence.** Code-verified:
- `case .background, .inactive:` (mafia_managerApp.swift:38) posts `.appWillEnterBackground` (:44);
- `prepareForBackground` cancels `tickTask` (Connection.swift:81-85);
- `handleAppResume` awaits `ensureValidSession()` before `startTicking()` (:72-79);
- `HOST_STALE_SECONDS = 15` (convex/lib/rules.ts:23).

Measured (PA-65): one `saveImmediately` of a 19-player game takes 415 µs.

**Impact.** A host who keeps an overlay up for about 10–20 s loses host to the next player for good, mid-game (see PA-06). The window depends on how old the last heartbeat was (0–5 s) and on peers checking every 5 s. For account users each blip costs one Clerk-to-Convex re-auth, or two at once inside a session, and the heartbeat restarts only after it finishes. Whether each re-auth sends a websocket Authenticate message is inferred. Save and audio costs are negligible.

**Solution.**
- Post `appWillEnterBackground` only on `.background`.
- Post `appDidBecomeActive` only after a real background. Track it with `@State var wasBackgrounded`, because the old phase is always `.inactive`.
- Keep a compact save on `.inactive` (drop `.prettyPrinted, .sortedKeys`), because a kill from the app switcher may not deliver `.background`.
- Keep `SoundManager.handleBackgrounding()` on `.inactive`, or replace it with an `AVAudioSession.interruptionNotification` observer. It is the only recovery after Siri or a call interrupts audio.
- Make `ensureValidSession()` single-flight with a stored `Task`. Optionally, start ticking before the auth refresh.

**Risk.** Low. Real backgrounding behaves as today. Moving the audio reset without adding an interruption observer would break sound after Siri.

#### PA-06 · The host role moves to another player after about 15 s in the background, with no way to take it back

**Severity:** Medium · **Status:** Recommended · **Evidence:** Code-verified; how often it happens is inferred · **Effort:** S

**Location:** `convex/sessions.ts:153-165`, `convex/lib/rules.ts:23`, `Core/Multiplayer/Store/MultiplayerGameStore+Connection.swift:111-127`, `convex/sessions.ts:259-273`

**Problem.** `claimHost` uses a fixed 15 s staleness threshold with no phase check, and the client stops heartbeating as soon as the app backgrounds. In the lobby, the host typically leaves the app to text the room code, because there is no Share button. iOS suspends the app and the first joiner takes host. Mid-game, the app never disables the idle timer, so a host whose phone auto-locks loses the narrator controls. The server can hand the lobby back through `returnToLobby`, but the client calls it only from Play Again.

**Evidence.** Code-verified:
- `if (hostSeat && nowAppleEpochSeconds() - hostSeat.last_heartbeat < HOST_STALE_SECONDS) fail(E.HOST_ACTIVE)` (convex/sessions.ts:159);
- the reclaim branch (:268) has one client caller, MultiplayerGameOverView.swift:239;
- `startGame` overwrites `original_host_user_id` (:243);
- the app never sets `isIdleTimerDisabled`.

**Impact.** Host moves after about 10–20 s away while another player has the app open. The original host loses Start, kick, End Game and the narrator buttons, and a friend inherits them along with bot driving. Nothing is lost and the game can finish. But host comes back only through Play Again. Once the interim host presses Start, the original host can no longer take the lobby back. Frequency is inferred. Short `.inactive` glances (PA-05) are a minor trigger.

**Solution.**
- Use a lobby-only threshold, e.g. `session.status === "waiting" ? 90 : HOST_STALE_SECONDS` at sessions.ts:159, mirrored in the client. Keep the successor freshness check at 15 s.
- On resume, after the first successful heartbeat, call `returnToLobby` if the session is waiting and the viewer is the original host but not the current host.
- Set `isIdleTimerDisabled` during an in-progress session.
- Send one last heartbeat inside `beginBackgroundTask`.

**Risk.** Failover is slower when a host really abandons the lobby, where nothing is time-critical. Auto-reclaim may surprise the interim host, so show a toast. Keeping the screen awake costs battery.

#### PA-07 · Network loss is invisible in multiplayer, and mutations never time out

**Severity:** Medium · **Status:** Recommended · **Evidence:** Code-verified (app code and pinned library source); the occasional fast error path is inferred · **Effort:** M

**Location:** `Core/Multiplayer/Services/SubscriptionSupervisor.swift:5-12`, `Core/Multiplayer/Store/MultiplayerGameStore+Connection.swift:48-68`, `Core/Backend/ConvexService.swift:42-53`, `Features/Multiplayer/Flow/MultiplayerLobbyView.swift:346-363`

**Problem.** The Rust client handles socket drops internally and only pauses values, so all three subscription supervisors stay `.live` during an outage. The banner appears only after a third failed retry, so a drop mid-game never shows "Reconnecting…". ConvexMobile 0.8.1 offers `watchWebSocketState()`, but the app never uses it. No layer times out a mutation. Unacknowledged mutations are kept and resent after reconnect.

**Evidence.** Code-verified:
- SubscriptionSupervisor.swift:9-10: "Transport drops are handled inside the Rust client and only pause values";
- `banner = banner || attempt >= 3` (Connection.swift:57);
- `client.mutation` is awaited with no bound (ConvexService.swift:48).

The pinned convex-swift 0.8.1 and convex-rs 0.10.3 sources show a 30 s server-inactivity threshold and FFI awaits that ignore cancellation. An occasional fast "channel closed" error is inferred.

**Impact.** On flaky venue Wi-Fi or cellular, players act on frozen state with no sign of it. Submit, Vote, Ready, Leave and End Game spin until the connection returns. Sometimes they fail with a generic error even though the mutation still applies later, and a retry then sends it twice. A second Leave tap is silently ignored (`guard !hasLeftSession`, MultiplayerLobbyView.swift:347). A dead socket takes up to 30 s to detect. No data is lost, and state recovers on reconnect.

**Solution.**
- Subscribe to `watchWebSocketState()` in `ConvexService.init` before any other call, because the subject does not replay. Show "Reconnecting…" after 2–3 s in `.connecting`. Treat the state as a hint, since states can be dropped.
- Also show the banner when any user mutation has been pending for more than about 5 s.
- Build timeouts as an unstructured continuation race with a resume-once flag, and report a timeout as "still sending". Do not use `withThrowingTaskGroup`: it waits for the FFI call.
- Scope `setReady` to the current phase before relying on replays.

**Risk.** A timed-out mutation may still apply, so the UI must not say it failed or offer a blind retry.

#### PA-08 · One-shot Convex queries and mutations have no timeout or cancellation, so screens spin while offline

**Severity:** Medium · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** M

**Location:** `Core/Backend/ConvexService.swift:27-40`, `Core/Backend/ConvexService.swift:123-141`, `Features/Stats/PlayerStatsView.swift:41-54`, `Core/Auth/Store/AuthStore.swift:79-83`

**Problem.** `ConvexService.query` turns a subscription into a single value with `.first().async()`, a bare `withCheckedThrowingContinuation` with no deadline and no cancellation handler. `mutation` has no time limit either. With the socket down nothing throws, so the callers' error alerts never appear.

**Evidence.** Code-verified:
- `return try await client.subscribe(to: name, with: prepare(args), yielding: type).first().async()` (ConvexService.swift:33-35);
- `PlayerStatsView.loadStats` clears `isLoading` only after the await (:41-54), and its `errorMessage` (:7) is never shown;
- launch restore awaits Convex inside `defer { isRestoringSession = false }` (AuthStore.swift:80-83), and the Online card is disabled while that flag is set (GameModeSelectionView.swift:79);
- the only timeout in the app belongs to the multiplayer subscription supervisor.

**Impact.** Offline or mid-reconnect:
- Player Stats, Custom Roles, Player Groups and the Setup load sheets spin with no error or Reload;
- Save stays disabled in the Add and Edit sheets;
- Online Create and Join spin.

When Clerk is reachable but Convex is not, the Online card stays disabled. Everything finishes on reconnect, and leaving a screen does not cancel the wait. The dropped-first-value race is real in the library but practically unreachable with today's callers.

**Solution.**
- Add one bounded query helper that races `for try await v in publisher.values` against a 10–15 s `Task.sleep`. Cancelling it tears down the subscription.
- Map a timeout to a network `BackendError`, so the existing alerts with Reload appear. Show `errorMessage` in `PlayerStatsView`.
- Treat a restore timeout as `restoreFailedTransiently`.
- For interactive mutations, use the PA-07 continuation race and say "may not have saved". Never auto-retry creates.
- Do not add a timeout to the stats sync.

**Risk.** A timeout that is too short causes false errors on slow networks. A timed-out mutation may still commit.

#### PA-09 · Cancel during an in-flight create or join leaves a hidden live session and an orphaned seat

**Severity:** Medium · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `Features/Multiplayer/Entry/CreateGameView.swift:127-136`, `Features/Multiplayer/Entry/CreateGameView.swift:174-210`, `Features/Multiplayer/Entry/JoinGameView.swift:137-146`, `Core/Multiplayer/Store/MultiplayerGameStore.swift:165-176`

**Problem.** Create and Join set `hasStartedSession` before the request, but the store sets `sessionId` only after it returns, and Cancel stays enabled throughout. Cancel mid-request calls `leaveSession()`, which throws `noActiveSession`. `try?` hides the error and the sheet closes. The request finishes anyway. `enter()` then starts three subscriptions and the 5 s heartbeat on a store that is still alive but shows nothing.

**Evidence.** Code-verified:
- `if hasStartedSession { Task { try? await multiplayerStore.leaveSession(); dismiss() } }` (CreateGameView.swift:128-132);
- only the Create button is ever disabled (:115);
- `guard let sessionId else { throw SessionError.noActiveSession }` (MultiplayerGameStore.swift:176);
- `enter()` (:165-172) does not check for cancellation after the await.

JoinGameView has the same code, and both `onDisappear` cleanups fail the same way.

**Impact.** The window is normally under a second, but offline it has no limit (PA-08), and that is exactly when users press Cancel. The phone keeps heartbeating until the user leaves the Online menu or kills the app, and each heartbeat re-runs all three subscriptions. Create leaves a waiting room that no one can see and that is never removed, because there is no cleanup cron. Join leaves a phantom seat in the intended room. If the host starts without removing it, the first vote deadlocks. The night deadlocks too if the seat drew a power role. Re-joining with the code or ending the game recovers.

**Solution.** Let the store own cancellation with a generation counter. Increment it in `enter()` and in a new `cancelPendingEntry()`, which Cancel and `onDisappear` call. If the counter changed by the time `call()` returns, send `leaveSession(sessionId: result.sessionId)` from a fresh `Task` and skip the subscriptions. Do not just disable Cancel unless create and join also get a timeout.

**Risk.** Low. A server-side leave with no seat does nothing, and re-joining restores the seat.

#### PA-10 · Three snapshots are applied separately with no equality check, causing redundant publishes and torn frames

**Severity:** Medium · **Status:** Recommended · **Evidence:** Measured (redundant publishes, decode cost) and code-verified; render count per update is inferred · **Effort:** S

**Location:** `Core/Multiplayer/Store/MultiplayerGameStore+Connection.swift:19-40`, `Core/Multiplayer/Store/MultiplayerGameStore.swift:114-149`, `Core/Multiplayer/Models/SessionSnapshots.swift:4-43`, `Features/Multiplayer/Flow/MultiplayerNightView.swift:28-30`

**Problem.** The client keeps three separate subscriptions. Each one reaches the main queue on its own, and its `apply` assigns a `@Published` value and runs `runHostAutomation()`. No snapshot model is `Equatable`, so unchanged values are assigned anyway. convex-rs re-sends every current value on every server update, including each member's 5 s heartbeat.

**Evidence.** Measured: 10 identical player snapshots fired 10 `objectWillChange` events. Decoding `[SessionPlayer]` takes 104.2 µs for 19 seats and 42.1 µs for 8.

Code-verified:
- `players = value` followed by `runHostAutomation()` (MultiplayerGameStore.swift:140-141);
- `struct SessionView: Decodable, Sendable` (SessionSnapshots.swift:4);
- the re-delivery behaviour, read in the convex-rs source.

The 1–3 view re-renders per server update are inferred.

**Impact.** On every server update each phone decodes three snapshots and publishes three times. The host plans bots three times. The PA-01 benchmark measured about 1.4–2.0 ms of main-thread time per redundant push, a minor client CPU cost; the heartbeat's real costs are network, function calls and battery (PA-01). Torn state is visual only, except when a player re-enters a running game. Night and Voting then read `myPlayer?.isAlive ?? false` before the roster arrives, so a living player sees "You are eliminated", usually for under 100 ms and at worst for about 5 s.

**Solution.**
- Add synthesized `Equatable`, and skip the assignment in each `apply` when nothing changed.
- First, stop the retries from depending on repeated values. BotDirector's `handled.remove(key) // Retry on the next snapshot.` (BotDirector.swift:70) and the role-reveal advance both rely on them. Call `runHostAutomation()` from `tick()` instead.
- In Night and Voting, treat a missing `myPlayer` as loading, as role reveal already does.

**Risk.** Deduplicating without the retry change can stall a night after a failed bot submission. `players` still changes on every heartbeat until the PA-01 presence split lands.

#### PA-11 · Nothing ties server JSON shapes to the Swift decoders, and a decode failure retries forever

**Severity:** Medium · **Status:** Recommended · **Evidence:** Code-verified; the absence of `returns` validators was measured in production · **Effort:** M

**Location:** `Core/Multiplayer/Services/SubscriptionSupervisor.swift:101-131`, `mafia_managerTests/Multiplayer/MultiplayerModelDecodingTests.swift:32-77`, `Features/Multiplayer/Flow/MultiplayerLobbyView.swift:71-81`, `Core/Backend/ConvexConfig.swift:6`

**Problem.** No Convex function declares a `returns` validator, and the Swift decoding tests use hand-written JSON. Nothing checks at runtime that the app and server versions match. A value can fail to decode, or the server can reject an old build's call with `ServerError`. Either way the supervisor retries forever, with backoff capped at 30 s, because only `ConvexError` is treated as final.

**Evidence.** Measured: the production `functionSpec` lists no `returns` validator.

Code-verified:
- `guard case .ConvexError(let data) = error else { return nil }` (SubscriptionSupervisor.swift:128);
- a test keeps `"Decoding failed"` retryable (SubscriptionSupervisorTests.swift:68);
- the banner has `onRetry: nil` (MultiplayerLobbyView.swift:80);
- `apiContractVersion` (ConvexConfig.swift:6) is read only by the deploy script.

Correction to the original finding: vitest already checks `is_me`, `ready_to_advance` and the outcome objects. The gap is keys it never checks (`last_heartbeat`, `joined_at`, `room_code`), date and id formats, and new enum values.

**Impact.** Latent: nothing is broken today. When it triggers, every multiplayer room shows "Reconnecting…" or a spinner forever, and the game stalls. The likeliest trigger is an old App Store build after a contract bump. That has happened once (contract 3 to 4), and a related decode mismatch also slipped past both test suites (commit `5d151f6`).

**Solution.**
- Generate fixtures from convex-test for each viewer projection, using fixed valid UUIDs and Apple-epoch timestamps, and decode them in a Swift test.
- After one confirming retry, stop retrying decode failures and show an "update the app" error. `InternalError` alone is too broad a signal, because ConvexMobile also uses it for subscribe failures.
- Compare `health:check` with a server-side minimum client contract (PA-30).
- Give the banner a Retry action, and add an `assertionFailure` in DEBUG builds.

**Risk.** Fixtures change whenever a shape changes on purpose, which is the point. The final error state needs a Retry button so a temporary error cannot strand the user.

#### PA-12 · Mafia bots lock onto the first human's pick and can outvote a human majority via the earliest-row tie-break

**Severity:** Medium · **Status:** Recommended · **Evidence:** Code-verified; frequency estimate inferred · **Effort:** S

**Location:** `Core/Multiplayer/Store/BotDirector.swift:124-148`, `convex/lib/rules.ts:104-122`, `convex/lib/rules.ts:138-141`, `Core/Multiplayer/Store/MultiplayerGameStore.swift:88-95`

**Problem.** On every snapshot the host's `nightPlans` plans each pending mafia bot as soon as any living human mafia has a committed row and copies that human's target. A bot that has a row leaves `pending` (`acted` filter, :124-126), so it is never re-planned. Bots therefore follow the first human to submit, not the "latest". The server's `majorityTarget` breaks a tie between human-voted leaders by the earliest-created row (rules.ts:119-121), which is that first human's row.

**Evidence.** `guard let latest = rows.filter({ humans.contains($0.actorPlayerId) })` (BotDirector.swift:142). Worked example: human mafia A, B, C plus 1 bot; A picks X, the bot follows, B and C pick Y; 2-2, A's row is earliest, X dies. The night grid counts only tentative drafts (`tentativeVoteCounts`), so humans never see the bot's committed vote. `mafiaBotsFollowTheLatestHumanTarget` (BotDirectorTests.swift:56-68) uses a static table, not ordered snapshots.

**Impact.** A human majority is overridden only when at least 3 living human mafia and 1 bot mafia disagree, so rooms of 9+ players with bots (a 6-human, 3-bot room deals a 3-human/1-bot mafia about 48% of the time, estimate). With 2 human mafia no majority is overridden, but the second human cannot sway the bots. Doctor and inspector are unaffected.

**Solution.** Preferred, on the server: in `buildNightRecord` (rules.ts:141), when any human mafia acted, count only human rows and use bot rows to break ties; update its vitest and ARCHITECTURE_NOTES. Client alternative: `guard humans.isSubset(of: acted)` in `nightPlans`, then target the human plurality with the server's tie-break and `canTarget`. Do not let bots resubmit: `play.ts:84` refreshes `created_at` and would shift the tie-break. Add an ordered-snapshot BotDirector test.

**Risk.** The server option changes a tested rule. The client option delays bot submits by one write wave (about 100 ms, estimate).

#### PA-13 · Solo and multiplayer use different win conditions after a night, and each mode's tests pin its own rule

**Severity:** Medium · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `Core/Gameplay/Store/GameStore.swift:731-762`, `convex/lib/rules.ts:164-172`, `Features/Intro/IntroView.swift:401`, `docs/ARCHITECTURE_NOTES.md:111-115`

**Problem.** Solo `evaluateWinners(startOfDay:)` ignores its parameter and ends the game at Mafia parity at every resolution point. The server keeps the older multiplayer rule: strict majority after a night, parity after a vote. The server also ends the game when only bots are alive (rules.ts:168); solo keeps cycling then (GameStore.swift:400-405), although solo games have bots too. Solo changed alone in 045c3a2; the server port kept the multiplayer rule.

**Evidence.** Solo `if mafiaCount >= nonMafiaCount` (GameStore.swift:756); server `if (startOfDay ? mafia > non : mafia >= non)` (rules.ts:170). `tests/convex/night.test.ts:179-180` asserts 1 vs 1 after a night is not a win; `GameStoreTests.swift:375-394` asserts 2 vs 2 after a night is a Mafia win. ARCHITECTURE_NOTES.md:114 documents the server rule; the in-app rules screen says "Equal or outnumber citizens" (IntroView.swift:401).

**Impact.** A multiplayer night ending N vs N plays an extra day that solo and the rules screen say should not happen. At 1 vs 1 this only delays the Mafia win; at 2 vs 2 or more citizens can win, because bot Mafia vote for random non-Mafia and can split. At most once per game; no performance cost.

**Solution.** Decide the rule first, then change one side. Parity everywhere: `mafia >= non` at rules.ts:170, rewrite night.test.ts:177-192 and ARCHITECTURE_NOTES:114, drop the dead Swift `startOfDay`. Strict after a night: restore the branch at GameStore.swift:755-761, update the solo test and the IntroView text. Decide explicitly whether solo ends bot-only games. A small shared table of (mafia, nonMafia, allBots, startOfDay) cases run by vitest and Swift Testing would stop future drift (see PA-100).

**Risk.** A user-visible rule change in one mode; add a release note. Saved solo games are re-evaluated at the next resolution, so no migration.

#### PA-14 · All-bot Mafia timer skips the "close your eyes / Start Night" gate and shows that every Mafia is a bot

**Severity:** Medium · **Status:** Recommended · **Evidence:** Code-verified; frequency inferred · **Effort:** S

**Location:** `Features/Night/NightWakeUpView.swift:60-75`, `Features/Night/NightWakeUpView.swift:858-876`, `Features/Night/NightWakeUpView.swift:24-38`, `Features/Night/NightWakeUpView.swift:166-186`

**Problem.** Solo only. Each night opens a fresh `NightWakeUpView` in `.nightWakeUp(.mafia)`. `onAppear` shows the sleep gate and, when every alive Mafia is a bot, also arms `scheduleAutoContinueForAllBots()`. The 4–6 s timer re-checks only the phase, which the gate does not change, so it calls `beginRoleAction(.mafia)` even if nobody tapped "Everyone Ready - Start Night". `showBotActing` then wins in `body` (:24) over the sleep screen (:33), and the gate cannot return that night.

**Evidence.** Timer guard: `if case .nightWakeUp(let currentRole) = self.store.state.currentPhase, currentRole == role` (:866-867), with no check of `showInitialSleepScreen`. The Mafia cue plays only in the Start Night closure (:179-180). The bot screen shows "Bot is Deciding..." with the role name for 3–5 s (BotDecisionService.swift:173-178).

**Impact.** With 2 Mafia, both are bots in about 21% of deals for 4 humans + 4 bots and about 54% for 2 humans + 6 bots, plus later nights after human Mafia die. If the host waits more than 4–6 s on the gate (frequency inferred), players with open eyes learn no human is Mafia, which breaks the hidden-role game; the cue is skipped or plays late. No crash or data loss; multiplayer unaffected.

**Solution.** Arm the timer after the gate. In `onAppear` and the matching `onChange` path, skip scheduling when the phase is `.nightWakeUp(.mafia)` and `showInitialSleepScreen` is true. In the Start Night closure, after `showInitialSleepScreen = false`, call `if shouldAutoExecuteForAllBots() { scheduleAutoContinueForAllBots() }`. Scope any timer backstop as `role != .mafia || !self.showInitialSleepScreen`: an unscoped check would block the inspector and doctor auto-continue after a cold relaunch mid-night, because the `@State` starts `true`.

**Risk.** Low. Recheck the all-bot inspector and doctor flows and the human-Mafia flow.

#### PA-15 · Template-default iPhone landscape pushes the only forward control of core-flow screens off-screen

**Severity:** Medium (auditor: High; verified: Medium) · **Status:** Recommended · **Evidence:** Measured (vote list, multiplayer role reveal); other screens code-verified by layout arithmetic · **Effort:** S

**Location:** `Project.swift:35-39`, `Features/Assignments/RoleRevealView.swift:54-66`, `Features/Multiplayer/Flow/MultiplayerRoleRevealView.swift:10-178`, `Features/Multiplayer/Flow/MultiplayerVotingView.swift:44-199`

**Problem.** `UISupportedInterfaceOrientations` allows landscape on iPhone, a value copied from the Xcode template; no view adapts to it. Seven core screens are non-scrolling `VStack { Spacer; fixed hero; Spacer; CTA }` stacks built from fixed frames (120–140 pt circles, a 280x380 card, 56 pt CTAs). In landscape the safe height is about 340 pt on a 6.1-inch phone, so the centred stack overflows and its bottom control lands below the screen edge; ScrollViews squeezed between fixed parts collapse.

**Evidence.** Measured (iPhone 17 rotated to 874x402 pt): the multiplayer vote list ScrollView is 0 pt tall for 828 pt of content (12 players); the multiplayer role reveal clips its avatar at the top and puts the confirm control below the screen edge. By arithmetic only: solo "Pass Phone" and host "Continue to Night" (`.frame(width: 280, height: 380)`, MultiplayerVoteDeathRevealView.swift:61) are fully off-screen; solo "Start Night" and "Reveal Deaths" stay partly tappable via the home-indicator strip.

**Impact.** Only an iPhone held sideways with rotation lock off. While rotated, solo cannot pass to the next player; a multiplayer player cannot confirm, pick a night target or vote, so server readiness gates hold the room; a rotated host cannot leave the vote reveal. Rotating back recovers instantly with no data loss. Frequency unknown, probably low.

**Solution.** Set iPhone `UISupportedInterfaceOrientations` to `["UIInterfaceOrientationPortrait"]` in `Project.swift:35-39`, keep the `~ipad` key, run `tuist generate`, and check the generated Info.plist. This also removes the iPhone landscape case in PA-77. Overflow-proofing for accessibility text sizes and iPad windows is separate, lower-priority hardening (`ScrollView` with `.defaultScrollAnchor(.center, for: .alignment)`).

**Risk.** Users lose landscape, which has no design today; iPad is unchanged.

#### PA-16 · SetupView's fixed-height, non-scrolling player list clips rows at large Dynamic Type sizes

**Severity:** Medium · **Status:** Recommended · **Evidence:** Code-verified (layout, regression origin); clipped amounts are estimates, not rendered · **Effort:** S

**Location:** `Features/Setup/SetupView.swift:136-138`, `Features/Setup/SetupView.swift:82-95`, `Features/Setup/SetupView.swift:128`, `Core/UI/DesignSystem.swift:79`

**Problem.** The player `List` sits inside the screen's `ScrollView` with `.scrollDisabled(true)` and exactly 64 pt per row. Each row is a `TextField` in `Design.Typography.body`, a Dynamic Type style, with 14 pt vertical padding and 6+6 pt row insets. The 64 pt constant fitted the old fixed 17 pt font; commit cc99682 made the font scale and kept the constant. Once rows exceed 64 pt, the bottom rows are clipped, and the List cannot scroll to them.

**Evidence.** `.frame(height: CGFloat(names.count) * 64)` (SetupView.swift:138); `.padding(.vertical, 14)` (:92); `static let body = Font.system(.body, design: .rounded)` (DesignSystem.swift:79). Nothing caps `dynamicTypeSize`. Verifier estimates from standard line heights: 60–62 pt per row by default; 3–6 pt over per row at xxxLarge (35–58 pt hidden with 10 rows); 24–28 pt over at AX3 (about 3 of 10 rows, or 5–6 of 19, hidden). VoiceOver access to clipped cells is unverified.

**Impact.** Users at xxxLarge or accessibility text sizes can name only the visible rows; from AX1 up, whole rows are unreachable. Every solo game passes through this screen. Blank rows do not block Continue, and bots or Load Group can fill seats. Confirm at xxxLarge and AX3 in the simulator.

**Solution.** Preferred: make the Setup screen one `List` with sections and `.scrollContentBackground(.hidden)`, which removes the fixed height and the nested scroll view. Minimal fix: scale only the text line, `@ScaledMetric(relativeTo: .body) var fieldLineHeight: CGFloat = 22` with `.frame(height: CGFloat(names.count) * (fieldLineHeight + 42))`. Scaling the whole 64 pt would waste about 60 pt per row at AX3.

**Risk.** The single-List option needs visual QA of the card styling; the minimal fix can be a few points off.

#### PA-17 · Repo lives in iCloud-synced `~/Documents`, so large git operations create conflict copies that break the build

**Severity:** Medium (auditor: High; verified: Medium) · **Status:** Recommended · **Evidence:** Measured (sizes, duplicates, timestamps); build-speed effect not measured · **Effort:** M

**Location:** `Project.swift:47-52`, `Project.swift:84-86`, `.gitignore:2-11`, `buildServer.json:15-16`

**Problem.** `~/Documents` is an iCloud Drive domain, so the whole repo, `.git` included, is synced. When git deletes and recreates many tracked files within seconds, iCloud keeps the losing version as a `* 2` copy, and it has also restored a file git deleted. The source globs then compile the copies. Gitignored heavy trees are synced too.

**Evidence.** Measured: in-repo `DerivedData` 437 MB (stale; builds use `~/Library/Developer/Xcode/DerivedData`), `node_modules` 131 MB, 45 untracked byte-identical duplicates, two ~830 KB `xcodemake … build.log` files at the root. Verifiers measured `Tuist/.build` at 426 MB and tied the copies' creation to a `git checkout main` plus `git pull` that rewrote 177 files. They also found `.git/index 2`, three older duplicate directories and `ClerkConvex.xcodeproj` restored after commit 9bf8eb2 deleted it.

**Impact.** Developer workflow only. A large git operation can produce copies that break the next `tuist generate` and build (measured failure in PA-03). About 1 GB of iCloud quota. Not supported: eviction risk (`~/Documents/Developer` is pinned "Keep Downloaded", no dataless files) and build slowdown (unmeasured).

**Solution.** Delete the `* 2*` artifacts, the restored `ClerkConvex.xcodeproj`, the stale `DerivedData/` and the build logs. Then `git clone` fresh into an unsynced folder such as `~/Developer/mafia_manager` (no Finder drag-move), copy ignored local state such as `.env.local` by name, run `npm ci && tuist install && tuist generate`, and regenerate `buildServer.json`. Keep agent worktrees outside synced folders. `.nosync` names or ignore xattrs only cut bulk; they do not stop copies of tracked files. Do not hide copies with exclusion globs.

**Risk.** Low. Commit or copy untracked work first; removing the old tree deletes it from iCloud on every synced Mac.

#### PA-18 · Unused ClerkKitUI dependency costs about half of each clean build and ships 0.9 MB of dead resources

**Severity:** Medium (auditor: Medium; verified: Low; raised by me on measured build data: the largest build-time win, with zero runtime risk) · **Status:** Recommended · **Evidence:** Measured · **Effort:** S

**Location:** `Project.swift:64`, `Tuist/Package.resolved:21-38`

**Problem.** The app target depends on `.external(name: "ClerkKitUI")`, but no source file has ever imported it; auth uses custom views and `ClerkKit`. ClerkKitUI pulls in Nuke, NukeUI and PhoneNumberKit. All four compile on every clean and Release build; the linker strips their code, but their resource bundles are still copied into the `.app`.

**Evidence.** `import ClerkKit` appears 4 times, `import ClerkKitUI` 0 times (code-verified). Measured, HEAD vs HEAD without ClerkKitUI: clean Debug build 55.3 → 30.7 s wall and 261 → 127 s CPU; a second pair under heavier load 120.1 → 55.0 s and 469 → 191 s CPU (−45–54% wall, −52–59% CPU); the build succeeds. Release: stripped binary identical; `.app` 22,916 → 22,008 KB (`Clerk_ClerkKitUI.bundle` 544 KB and PhoneNumberKit bundle 368 KB gone); zipped IPA 5,272,245 → 5,028,318 B (−4.6%).

**Impact.** Mainly developer and build-machine time: about half of a clean Debug build (measured); Release and archive builds compile the same 222 unused object files. Incremental builds are already fast (no-op 2.9 s, leaf view edit 4.0 s, measured), so daily impact is smaller. Users get a slightly smaller download; launch, memory and code size are unchanged.

**Solution.** Delete `.external(name: "ClerkKitUI"),` at `Project.swift:64`, run `tuist install && tuist generate`, and build. `Package.resolved` keeps the nuke and phonenumberkit pins and `tuist install` still fetches them, because clerk-ios declares them at package level; only the build graph shrinks. Re-add ClerkKitUI only if a prebuilt `AuthView` or `UserButton` is adopted. See PA-80 for the related x86_64 simulator cost.

**Risk.** Very low: any missed usage fails the build at once. The vendored ClerkKitConvex imports only ClerkKit and ConvexMobile.

#### PA-19 · No CI for build, typecheck or tests, and `convex:deploy` ships to production without running backend tests

**Severity:** Medium · **Status:** Recommended · **Evidence:** Code-verified; suite timings measured · **Effort:** M

**Location:** `package.json:8-13`, `AGENTS.md:48-61`, `docs/SESSION_CHANGES.md:720-724`, `scripts/e2e/verify-deployment.mjs:12-17`

**Problem.** Main has no CI configuration. `npm run convex:deploy` is plain `convex deploy`: the Convex CLI typechecks `convex/` (inferred from CLI behaviour, corroborated in SESSION_CHANGES), but nothing runs vitest or checks the API contract. AGENTS.md lists `tuist test mafia_manager` but not `npm run test:backend`, and selective testing can make that command run nothing. `tests/convex/*.ts` and `scripts/*.mjs` are never typechecked. `verify-deployment` checks the Debug host unless `CONVEX_AUDIT_URL` is set and does not print the URL it checked.

**Evidence.** No `.github` directory; `"convex:deploy": "convex deploy"` (package.json:10); SESSION_CHANGES.md:721-724: the pruned scheme "has **no test action**"; `convex/tsconfig.json:23` covers only `convex/`; `apiContractVersion` (ConvexConfig.swift:6) has no runtime reader (PA-30). Measured: vitest 47/47 in 1.03 s, `tsc` 0.45 s, unit tests 101/105 pass (4 skipped) in a ~100–108 s `xcodebuild test` run.

**Impact.** Regression-escape risk, no runtime cost. A backend change can reach production with the vitest cases never run, and nothing confirms the contract the shipped app expects. SESSION_CHANGES shows manual checks are usually done, so the risk is moderate. CI would not catch the iCloud duplicates (PA-03); they are untracked.

**Solution.** Add an ubuntu job on every PR: `npm ci && npm run test:backend && npx tsc -p tests/tsconfig.json --noEmit`, with `tests/tsconfig.json` extending `../convex/tsconfig.json` (`allowJs`/`checkJs` for `.mjs`). Add a macOS job on PRs to main or nightly with selective testing off (Tuist 4.x `--no-selective-testing`; confirm with `tuist test --help`). Gate deploy inside the script (`npm run test:backend && convex deploy && CONVEX_AUDIT_URL=<prod URL> node scripts/e2e/verify-deployment.mjs`); a `predeploy` hook would not fire for `convex:deploy`. Print the checked URL; add the missing commands to AGENTS.md.

**Risk.** macOS CI minutes cost money; live suites must use dev secrets and never target production.

### 4.3 Low severity · Backend (Convex)

#### PA-20 · `getRoundState` reads the whole roster, all round actions and all tentatives for every viewer, then filters

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Code-verified; per-call read sizes from an auditor's synthetic harness (inferred) · **Effort:** S

**Location:** `convex/views.ts:13-22`, `convex/views.ts:66-120`, `convex/lib/projections.ts:111-121`

**Problem.** Visibility is applied after the reads. Every call goes through `loadMember`, which collects the whole `session_players` range, then reads all of the round's actions and up to three tentative ranges. As a result, every seat write re-runs every member's query: each human's 5 s heartbeat, every join and every ready toggle. Yet outside voting, a non-host needs only its own seat.

**Evidence.** `views.ts:18` `const seats = await listSeats(ctx, session.id);`, filtered afterwards at `views.ts:117`. Measured: results are ~105–136 B early in a game, and 72 h of insights show no OCC conflicts or read-limit warnings. An auditor's synthetic harness put a citizen's night read set at 39 docs / ~18 KB.

**Impact.** About 672 redundant runs/min at 8 humans and ~4,100/min at 19, from heartbeats alone (code-derived estimate). This overlaps PA-01. The cost is server-side only: function calls, CPU and bandwidth.

**Solution.** Read the caller's seat with `by_session_user`, as `getSessionView` does. Call `listSeats` only for the host or during `voting`. At night, non-hosts should read only their own role's action and tentative ranges, and citizens should read none. Drop the `vote` tentative read, which always comes back empty.

**Risk.** Privacy-critical: extend `tests/convex/privacy.test.ts` (citizen at night, dead mafia, non-host around `allVoted`, game over).

#### PA-21 · Bots submit one mutation each, so a bot burst costs one commit and one `getRoundState` wave per bot

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** M

**Location:** `Core/Multiplayer/Store/BotDirector.swift:63-100`, `Core/Multiplayer/Store/MultiplayerGameStore.swift:144-149`, `convex/play.ts:26-99`

**Problem.** `BotDirector.run` starts one `Task` and one `play:submitAction` per pending bot. Each call re-reads the session, the caller and the roster, then commits one row. Each commit re-runs `getRoundState` for every member. The host sees every row, so it receives up to B changed snapshots. Each one is assigned without an equality check and re-runs `runHostAutomation` (PA-10).

**Evidence.** `BotDirector.swift:64-73` starts one `Task` per plan, `play.ts:37` calls `requireRoster`, and `MultiplayerGameStore.swift:147` does `roundState = value`. Verifier corrections: non-hosts mostly get unchanged results, no UI shows live vote counts, and a failed submit retries on the next heartbeat-driven snapshot (~1–5 s) by design (`BotDirectorTests.swift:212`).

**Impact.** Small. The UI caps bots at 10 (`CreateGameView.swift:74`; the server allows 18). Verifier estimate: ~1 s of Convex compute per phase with 4 humans, over 0.2–0.5 s, plus up to B host re-renders.

**Solution.** First make `RoundState` and its rows `Equatable` and return early from `apply(roundState:)` when unchanged. Optionally add a host-only `play:submitBotActions` that validates all items against one roster load and upserts them in one transaction with per-item results, keeping the inspector one-check rule and the vote fallback.

**Risk.** The batch needs partial-failure handling and test changes; the `Equatable` guard is near risk-free.

#### PA-22 · `is_online` is never written false, so the lobby's online dot is always green for human players

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `convex/sessions.ts:175`, `convex/lib/projections.ts:99`, `Core/Multiplayer/Models/SessionPlayer.swift:14`, `Features/Multiplayer/Flow/MultiplayerLobbyView.swift:385`

**Problem.** Seats get `is_online: true` on insert, on re-entry and on every heartbeat, and no server path ever sets it to false. The lobby maps the field straight to its green or grey dot. A player who killed the app or lost signal therefore still shows as online.

**Evidence.** The only writes are at `sessions.ts:44`, `:106` and `:175` (`{ last_heartbeat: nowAppleEpochSeconds(), is_online: true }`). The only `false` is in `tests/convex/sessions.test.ts:37`. The dot is drawn at `MultiplayerLobbyView.swift:385`. The auditor's dev count of 49 stale "online" seats could not be re-run.

**Impact.** UI correctness only. Leaving deletes the seat, and the host row already has a heartbeat-based offline badge. So only non-host humans who disconnected silently are mislabelled. The field adds no cost, because it travels in the heartbeat patch. Ghost seats getting roles is PA-02, a separate finding.

**Solution.** Derive the dot on the client from the age of `lastHeartbeat`. Reuse the 5 s tick and `hostOfflineThreshold` (`MultiplayerGameStore+Connection.swift:111-137`), and publish offline ids only when they change. Apply the PA-40 clock-skew fix as well.

**Risk.** `SessionPlayer.isOnline` is a non-optional `Bool`. Removing the field from `playerForViewer` would break `getPlayers` decoding on every installed build.

#### PA-23 · No data lifecycle: abandoned rooms, seats, actions and orphaned guest users are never cleaned up

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Measured (dev table counts) and code-verified · **Effort:** M

**Location:** `convex/lib/transitions.ts:40-52`, `convex/lib/transitions.ts:62-77`, `convex/sessions.ts:18-28`, `Core/Auth/Store/AuthStore.swift:361-367`

**Problem.** Rows are removed only on leave, kick or cancel; there is no `crons.ts` or scheduler use. `finishGame` keeps seats, actions and tentatives, cancelling keeps the session row, and `game_sessions` rows are never deleted, so room codes are never reused. "Clear Guest Data" leaves the server guest row and its data behind.

**Evidence.** Measured on dev: users 330; game_sessions 224 (207 cancelled, 9 completed, 8 waiting); session_players 61; game_actions 50; tentative_selections 4; player_stats 58. `transitions.ts:51` only patches seats; `AuthStore.swift:362` says "The server keeps the guest row."

**Impact.** No performance cost at about 1 KB per room. "Return to Menu" cleans up, so leftovers come from killed apps. Rare effects: joinable ghost lobbies, rooms stuck in `in_progress`, and the stale seats behind PA-29.

**Solution.** Add `convex/crons.ts` with an hourly internal mutation that works in batches (`.take(100)`). It should cancel rooms whose human heartbeats are all older than ~6 h (via `cancelSessionAndRemovePlayers`), delete seats in completed rooms after ~24 h, hard-delete cancelled and completed sessions after ~30 days, and optionally delete guests that own nothing.

**Risk.** Judge staleness by seat heartbeats, not by `session.updated_at`.

#### PA-24 · Same-target taps and re-submits always rewrite their row and re-run every member's `getRoundState`

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `convex/play.ts:125-127`, `convex/play.ts:83-84`, `Features/Multiplayer/Flow/MultiplayerNightView.swift:548-564`, `Features/Multiplayer/Flow/MultiplayerVotingView.swift:83-89`

**Problem.** `setTentativeSelection` always patches `updated_at`, and re-submitting through `submitAction` always bumps `created_at`, even when the target is unchanged. The night grid sends one mutation per tap. The host's vote list sends `play:submitAction` on every tap, including taps on the player already selected. Each write re-runs `getRoundState` for every member.

**Evidence.** `play.ts:125` builds `{ target_player_id, updated_at: nowAppleEpochSeconds() }` and patches without checking. `play.ts:84` bumps `created_at`. The night tap handler checks only `!isSubmitting && !hasSubmitted` (`MultiplayerNightView.swift:549`). The bump also moves the actor in the earliest-first tie-break (`rules.ts:119-121`).

**Impact.** Small: one mutation and up to H query re-runs per redundant tap. The verifier estimates 100–190 extra runs per phase in a worst-case 19-player room. The tie-break quirk needs two tied humans of the same role, one of whom retries after an error.

**Solution.** In both mutations, return early when `existing && existing.target_player_id === args.target_player_id`. Keep bumping `created_at` when the target really changes, because BotDirector relies on it. On the client, skip the send when the tapped player is already selected. Avoid a debounce: it would delay the user's own count badge, which comes from the server.

**Risk.** Negligible.

#### PA-25 · Redundant prefix indexes and unused indexes in `schema.ts` add write overhead

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; patch-time index cost inferred · **Effort:** S

**Location:** `convex/schema.ts:122-126`, `convex/schema.ts:144-148`, `convex/schema.ts:161-175`, `convex/schema.ts:186-193`

**Problem.** Every insert and delete maintains each index, yet several are redundant or unused. `game_actions.by_session_round_type_phase` and `by_session` are prefixes of `by_unique_action`; `tentative_selections.by_session_phase_type` is a prefix of `by_actor`; the library tables' `by_user` indexes are prefixes of their compound indexes. `game_sessions.by_status`, `session_players.by_session_player` and two `by_app_id` indexes are never queried, and two more `by_app_id` indexes serve only tests.

**Evidence.** `schema.ts:163-175` declares `[session_id, round_id, action_type, phase_index]`, then the same fields plus `actor_player_id`. A grep of `convex/` and `tests/convex` finds no use of `by_status` or `by_session_player`. Refactor 95456f8 left `by_session_player` orphaned.

**Impact.** Negligible: a few hundred extra index-entry writes per game. This is schema hygiene.

**Solution.** Point these queries at the compound indexes with the same `eq` prefix: `night.ts:31`, `voting.ts:33`, `views.ts:79/91`, `transitions.ts:13/21`, and the `by_user` queries in `stats.ts` and `users.ts`. Every consumer re-sorts its results, so nothing changes. Then drop the redundant and unused indexes.

**Risk.** Deploy in two steps: change the queries first, then remove the indexes.

#### PA-26 · `submitAction` and `setTentativeSelection` read the whole roster when they need two or three seats

**Severity:** Low · **Status:** Needs Further Investigation · **Evidence:** Code-verified (read set); OCC effect inferred · **Effort:** S

**Location:** `convex/play.ts:36-41`, `convex/play.ts:110-114`, `convex/lib/guards.ts:35-41`, `convex/lib/rules.ts:201-220`

**Problem.** Both mutations call `requireRoster`. It awaits `getSession`, `requireCaller` and `listSeats` one after another and collects every seat, but validation uses only the actor and the target. Because the full `by_session` range is in the read set, a concurrent seat write can force a transparent OCC re-execution. Examples are another player's heartbeat, or the `setReady` sent after each submit.

**Evidence.** `play.ts:37` and `:111` both call `await requireRoster(ctx, args)`. `rules.ts:212` and `:216` look up only the actor and the target. A point-read guard, `requireSeat`, already exists (`guards.ts:24-33`). Convex insights show 0 OCC conflicts in 72 h, under low traffic (measured).

**Impact.** Each call reads about N+3 docs instead of about 6 (N ≤ 19). The verifier estimates, without measuring, that 1–3% of calls retry with 6 humans and 4–11% with 19, at about 20 ms per retry. To settle priority, check the dashboard during a busy game: OCC retries and documents read per `play:submitAction` call.

**Solution.** Reuse `requireSeat`. Read the actor and the target with `by_session_player` `.first()`, and pass those seats to `requireActor` and `validateGameAction`. Keep the error strings identical.

**Risk.** Low. `tests/convex/play.test.ts` covers the rejection paths.

#### PA-27 · Guest merge patches every session the guest ever hosted, including cancelled rooms

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `convex/users.ts:232-245`, `convex/sessions.ts:66-67`, `convex/schema.ts:124-125`

**Problem.** `mergeGuestIntoAccount` collects and patches every `game_sessions` row where the guest is `host_user_id` or `original_host_user_id`, whatever the room's status. Sessions are never deleted (PA-23), and `createSession` sets both fields. Most rooms are therefore read and patched twice, and each rewrite bumps `updated_at` on dead rooms.

**Evidence.** `users.ts:237` runs `await ctx.db.patch(room._id, { host_user_id: account.id, updated_at: nowAppleEpochSeconds() });` for every hosted room. `:244` repeats it for `by_original_host`. Nothing joins host ids to `users`. The verifier corrected one point: the seat loop does not grow with cancelled rooms, because seats are deleted when a room is cancelled or a player leaves.

**Impact.** A one-time cost per guest at sign-in. Each room the guest ever created costs about 2 reads and up to 2 writes (~0.7–1.7 KB each), which is typically a few dozen writes in total. No effect on gameplay.

**Solution.** Patch only rooms that can still matter: waiting rooms, in-progress rooms, and completed rooms where the guest still has a seat. Patch each room once, with both fields. Do not bump `updated_at` on dead rooms.

**Risk.** Negligible. Keep `tests/convex/stats.test.ts:141-153` passing.

#### PA-28 · `merged_guest_digests` grows without bound on the account document

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `convex/users.ts:247`, `convex/users.ts:154-160`, `convex/schema.ts:33-34`, `convex/lib/identity.ts:28-35`

**Problem.** Each successful merge appends a 64-hex digest to the account's `merged_guest_digests`, and nothing ever trims the array. `getAccountUser` loads this document on most signed-in calls, so its size grows with every lifetime merge. Convex documents a limit of 8,192 array elements. Past that limit the patch would throw, and every later merge into that account would fail.

**Evidence.** `users.ts:247` sets `merged_guest_digests: [...(account.merged_guest_digests ?? []), digest]`. The only reader is the retry check at `users.ts:157`. The array limit comes from Convex documentation; it was not confirmed in source.

**Impact.** Negligible. Each entry is about 67 B, and an entry is added only when a guest is merged into the account, so 50 merges add ~3.4 KB. The read set stays at one document. Only the account's owner can push it toward the cap.

**Solution.** Keep only the last 20 entries: `[...prev, digest].slice(-20)`. A retry after a lost response arrives at the next launch or sign-in. A very late retry gets `GUEST_NOT_FOUND`, which `AuthStore.swift:314-316` already handles silently. No migration is needed. Leaving the code as it is would also be defensible.

**Risk.** Negligible.

#### PA-29 · A guest-merge seat conflict, even in an old finished room, fails on every launch with no actionable message

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Code-verified; trigger frequency inferred · **Effort:** S

**Location:** `convex/users.ts:163-173`, `convex/lib/identity.ts:37-41`, `Core/Auth/Store/AuthStore.swift:309-321`, `Features/Settings/SettingsView.swift:49-69`

**Problem.** The merge aborts with `MERGE_SEAT_CONFLICT` if the account holds a seat in any room where the guest also has one, whatever the room's status. Until it succeeds, the client keeps sending the guest proof, which the server prefers over the Clerk identity. The device acts as the guest and hides the account's stats, configs and groups, and every launch fails the same way.

**Evidence.** `users.ts:172` runs `if (existingSeat) fail(E.MERGE_SEAT_CONFLICT);` with no status check, and `identity.ts:40` tries the guest proof first. The message (`errors.ts:9`) names no room; Settings offers only Retry.

**Impact.** Rare: it needs a stale seat (app killed before leaving, or a second device) in a room where the same person holds the other identity. Recovery (re-enter the room by code, then leave) exists but is undiscoverable. Nothing is lost unless the user signs out.

**Solution.** In completed, cancelled or waiting rooms, have the server keep the seat with the newer `last_heartbeat`. Refuse the merge only for live in-progress games. At minimum, put the room code in the message and add a "Discard guest progress" action with a confirmation step.

**Risk.** Deleting the seat a device is viewing looks like a kick. `stats.test.ts:141-153` will need updating.

#### PA-30 · The app never checks the backend API contract; old builds will fail with generic errors after a bump

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `Core/Backend/ConvexConfig.swift:6`, `convex/health.ts:4-13`, `scripts/e2e/verify-deployment.mjs:4-17`, `Core/Backend/BackendError.swift:18-33`

**Problem.** Only the deploy script reads `ConvexConfig.apiContractVersion = 4`, by regex-parsing the Swift file. The app itself never calls `health:check`. After a breaking contract change, older builds call functions and argument validators that have changed. `BackendError` turns those failures into "Something went wrong", and the user is never told to update.

**Evidence.** `ConvexConfig.swift:6` is the only Swift reference. `verify-deployment.mjs:11` runs `config.match(/apiContractVersion = (\d+)/)`. `docs/SESSION_CHANGES.md:10` says "Old app builds (contract 3) stop working once contract 4 is deployed." `BackendError.swift:27-32` replaces any message that does not come from a `ConvexError`.

**Impact.** No users are affected yet, because `SESSION_CHANGES.md` records that no Convex-backed build has shipped. After the first Convex release, each breaking change would partly break online features on outdated builds. Solo play is unaffected.

**Solution.** Call `health:check` once per launch, off the critical path. Add a server-side `min_client_contract` and block when `apiContractVersion < min_client_contract`; strict equality would block staged rollouts. Block only online features. The check has to ship in the first Convex-backed release, or it protects no one.

**Risk.** Block only on an explicit mismatch, never on an error or a timeout.

#### PA-31 · Finish Night is two serial host mutations, adding a round trip and an extra invalidation wave to every night

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; latency figures inferred · **Effort:** S

**Location:** `Core/Multiplayer/Store/MultiplayerGameStore+HostPhases.swift:38-45`, `convex/night.ts:14-45`, `convex/night.ts:47-108`

**Problem.** `completeNightPhase` awaits `recordNightActions` before sending `resolveNightAtomic`, so the transition every phone waits for needs two host round trips. The first commit patches the session document, which all three view queries read. That re-runs 3×H queries and pushes every member a `getSessionView` whose only change is `updated_at` (plus `night_history` for the host).

**Evidence.** `HostPhases.swift:43-44` awaits `recordNightActions(...)` and then `resolveNightAtomic(...)`. `night.ts:42` patches `night_history` and `updated_at`. Both endpoints are idempotent per round.

**Impact.** Each night, every player waits about one extra round trip plus 10–30 ms of mutation time (the verifier's inference). On the audit network I measured a 42 ms ICMP round trip to eu-west-1 and estimated 55–75 ms per sequential mutation.

**Solution.** Add one server mutation, for example `night:finishNight`, that runs the existing record logic and then the resolve logic in one transaction, and keep both old endpoints. Record-then-resolve still happens on the server, but the documented host call sequence changes. AGENTS.md, CLAUDE.md and `docs/ARCHITECTURE_NOTES.md` therefore need updating, with the owner's sign-off. Do not pipeline the two calls with `async let`. The child tasks race, and if resolve arrives first it fails with `NIGHT_NOT_RECORDED`.

**Risk.** Low. Both endpoints are idempotent, so retries stay safe.

### 4.4 Low severity · Multiplayer client

#### PA-32 · Every Convex request reads the Keychain and hashes the guest secret on the main actor

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Measured (259 µs per request, simulator) · **Effort:** S

**Location:** `Core/Backend/ConvexService.swift:80-87`, `Core/Auth/Store/AuthStore.swift:30-32`, `Core/Auth/Store/AuthStore.swift:348-359`, `Core/Auth/Services/KeychainHelper.swift:53-78`

**Problem.** `ConvexService.prepare` calls `guestProofProvider` on every query, mutation and subscribe. That recomputes `currentGuestSecretHash` each time: a `SecItemCopyMatching` call, which blocks on securityd, then SHA-256. A signed-in account pays one Keychain lookup per request just to learn that no guest merge is pending. While a merge is pending, each request costs two.

**Evidence.** `ConvexService.swift:83` calls `let proof = guestProofProvider?()`. `AuthStore.swift:349` runs `guard let secret = try? keychain.load(forKey: KeychainKeys.guestSecret)`. I measured 259 µs per request on the main actor (simulator).

**Impact.** In steady state this is about 0.2 lookups per second from the heartbeat, plus one per user action. The worst normal burst is 10 back-to-back lookups at vote start with the maximum 10 bots: 10 × 259 µs ≈ 2.6 ms (estimate). The secret changes in only two places, so the work is redundant. Users are unlikely to notice.

**Solution.** Cache the hash in `AuthStore` as `private var cachedGuestSecretHash: String??`. Fill it lazily, caching only a successful read or item-not-found. Set it in `loadOrCreateGuestSecret` and clear it in `clearGuestData`.

**Risk.** Low. Every code path that writes the Keychain key must also update the cache. The existing tests remain valid.

#### PA-33 · Each foreground in a multiplayer session runs `ensureValidSession` twice concurrently, with no coalescing

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Code-verified, including the pinned Clerk and Convex package sources; extra server re-run inferred · **Effort:** S

**Location:** `Core/Auth/Store/AuthStore.swift:75-78`, `Core/Auth/Store/AuthStore.swift:124-135`, `Core/Multiplayer/Store/MultiplayerGameStore.swift:53-55`, `Core/Multiplayer/Store/MultiplayerGameStore+Connection.swift:72-79`

**Problem.** Every time the scene becomes `.active`, the app posts `appDidBecomeActive`, including after brief `.inactive` blips. AuthStore's observer and `MultiplayerGameStore.handleAppResume` both respond by calling `ensureValidSession()`, and nothing stops the two calls from overlapping. For signed-in accounts that means two `loginFromCache` calls. If the refresh fails, two `restoreSession` runs follow. Each one bumps `identityRevision`, which restarts all three subscriptions.

**Evidence.** `AuthStore.swift:77` and `MultiplayerGameStore+Connection.swift:75` both await `ensureValidSession()`. Verifier corrections: Clerk's `SessionTokenFetcher` joins concurrent token fetches, so at most one Clerk HTTP request is made; guests return early (`AuthStore.swift:129`); and the heartbeat delay on resume comes from awaiting auth, not from the duplicate call.

**Impact.** Each resume costs one redundant `setAuthCallback` and probably one extra re-run of three small queries (inferred). On the failure path, each subscription restart risks the 15 s first-value stall. This is a hygiene issue, not a cost problem.

**Solution.** Keep the running call in `private var ensureTask: Task<Void, Never>?`. Later callers await it, and it clears itself when done. Keep both callers. Bump `identityRevision` only when the identity really changes (PA-42).

**Risk.** Low. Keep `resumeDetectsARevokedSession` and `foregroundRetriesAnAccountRestoreThatFailedTransiently` passing.

#### PA-34 · Coarse `ObservableObject` store republishes every heartbeat-only `players` change to all multiplayer views

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Measured; mechanism code-verified · **Effort:** S

**Location:** `Core/Multiplayer/Store/MultiplayerGameStore.swift:8-29`, `Core/Multiplayer/Store/MultiplayerGameStore.swift:136-142`, `Core/Multiplayer/Store/MultiplayerGameStore+Connection.swift:111-127`, `convex/lib/projections.ts:101`

**Problem.** `apply(players:)` assigns every snapshot without comparing, and no model is `Equatable`. `getPlayers` carries `last_heartbeat`, so each human heartbeat (every 5 s) pushes an array that differs only in a field no view renders. Each push re-evaluates the lobby router and the current phase view. `checkHost()` also reassigns `isHostOffline` every tick, even when unchanged.

**Evidence.** `MultiplayerGameStore.swift:140` `players = value`. `Connection.swift:118` reassigns `isHostOffline`. Measured: 10 identical player snapshots fired 10 `objectWillChange`. Measured (Release, 12 players): each redundant push costs about 1.4–2.0 ms of main-thread time. Lobby `PlayerRow` bodies are not re-evaluated.

**Impact.** About H/5 pushes per second per client (H = humans), measured at about 5 ms CPU/s at 12 humans. Nothing visible changes. The heartbeat's network cost (PA-01) dominates.

**Solution.** `Equatable` alone won't help, because `lastHeartbeat` always differs. Keep a plain `lastHeartbeats: [UUID: Date]`, assign `players` only when the seats differ ignoring it, and have `checkHost`/`nextHost` read the map. Guard `if isHostOffline != offline`, and drop the unused `isRealtimeConnected`. `@Observable` is an optional follow-up (effort M; it replaces the `$sessionView` waiter at `:280`).

**Risk.** Host failover breaks if `checkHost`/`nextHost` keep reading `players`. If you do the migration, re-test the night view's `.onChange` chains.

#### PA-35 · Night actions and votes send a `setReady` write that nothing in night or voting reads

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `Features/Multiplayer/Flow/MultiplayerNightView.swift:635-636`, `Features/Multiplayer/Flow/MultiplayerNightView.swift:679-693`, `Features/Multiplayer/Flow/MultiplayerVotingView.swift:252-261`, `convex/views.ts:100-108`

**Problem.** After each night action and each non-host vote, the views call `setReadyStatus(true)`. Citizens also call it through `autoReadyIfPassive`. Readiness in night and voting comes from action and vote rows (`convex/lib/rules.ts:77-101`); the server reads `is_ready` only for role-reveal readiness and night masking. Each write patches the seat, which re-runs `getPlayers`/`getRoundState` for every member.

**Evidence.** `MultiplayerNightView.swift:636` `try await multiplayerStore.setReadyStatus(true)`. `MultiplayerVotingView.swift:254` `try? await multiplayerStore.setReadyStatus(true)`. `convex/sessions.ts:184` patches the seat unconditionally. No client code reads `isReady` in night or voting (grep).

**Impact.** About 2H−2 unneeded mutations per day/night cycle, roughly 5–10% on top of heartbeat seat writes (verifier estimate). The non-host "Vote Submitted" screen waits one extra mutation; I estimate about 55–75 ms per sequential mutation on the test network. At night, `restoreSubmittedAction` normally shows success before `setReady` returns.

**Solution.** Delete both calls and set `hasSubmitted` as soon as `submitVote` returns. Delete `autoReadyIfPassive`, its `.task` call, the two `.onChange` hooks (`:236-241`) and `autoReadyApplied` (`:9`). Keep the `enterRound` reset: `night.test.ts:175-176` asserts it.

**Risk.** Low. Any future night or voting logic that reads `is_ready` would need the write back.

#### PA-36 · Reveal Deaths, Start Voting and Continue to Night drop mutation errors with `try?`

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `Features/Multiplayer/Flow/MultiplayerLobbyView.swift:630-632`, `Features/Multiplayer/Flow/MultiplayerLobbyView.swift:814-816`, `Features/Multiplayer/Flow/MultiplayerVoteDeathRevealView.swift:328-333`, `Features/Multiplayer/Flow/MultiplayerRoleRevealView.swift:209-220`

**Problem.** Host-only transitions run as `Task { try? await multiplayerStore.revealDeaths() }` (`:631`) and `startVoting()` (`:815`), with no in-flight state or progress indicator. Continue to Night already has an in-flight guard (`.disabled(isTransitioning)`, `:351`) but discards the error at `:331`.

**Evidence.** The verifier showed most failures already surface elsewhere. A lapsed sign-in shows the banner with Retry (`MultiplayerGameStore.swift:114-122`). MOVED_ON, HOST_ONLY and NOT_ACTIVE re-route through subscriptions. `forceStartNight` is retried by `runHostAutomation`. Duplicate taps are server no-ops with no writes (`convex/phases.ts:23`). End Voting already shows its errors.

**Impact.** Rare. If an error doesn't also change subscribed state (a server error, `currentRoundId()` throwing, a decode error like the one fixed in 5d151f6), the host sees nothing and the table waits. Re-tapping is a safe retry.

**Solution.** Copy the pattern from `MultiplayerVotingResultsView.swift:98-124` (`isTransitioning`, `transitionError`, `.disabled`, `ProgressView`, inline error) to the two lobby buttons. Use do/catch at `:331`. Treat MOVED_ON, NOT_ACTIVE and HOST_ONLY as silent success. Don't add `recoverIdentity()` at each call site; a shared button type is optional.

**Risk.** UI-only. Keep the server idempotency these calls rely on.

#### PA-37 · Non-host vote rows stay tappable during submit, so "You voted for X" can name a player other than the one recorded

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `Features/Multiplayer/Flow/MultiplayerVotingView.swift:80-90`, `Features/Multiplayer/Flow/MultiplayerVotingView.swift:100-118`, `Features/Multiplayer/Flow/MultiplayerVotingView.swift:141-146`, `Features/Multiplayer/Flow/MultiplayerVotingView.swift:238-272`

**Problem.** `submitVote` captures the target (`let targetToSubmit = explicitTarget ?? selectedTargetId`, `:243`), then awaits two serial mutations. During that time row taps still set `selectedTargetId`; there is no `isSubmitting` guard like the night grid's (`MultiplayerNightView.swift:549`). The Submit button only becomes `.disabled`; its label and background don't change, so the tap looks ignored. The confirmation then reads `selectedTargetId` (`:143`).

**Evidence.** The server stores the target captured at Submit (`convex/play.ts:83-84`). The results screen shows only tallies, so a wrong label is never corrected.

**Impact.** Only a non-host who picks another row inside the window is affected. The window is normally a few hundred ms (verifier estimate) and longer while reconnecting. The recorded vote is right; only the label is wrong. The host has row checkmarks and End Voting state.

**Solution.** Add `guard !isSubmitting else { return }` to the non-host row action. Copy the night Submit pending label (`ProgressView`, "Submitting...", dimmed background). Set `hasSubmitted` once `submitVote` returns, without waiting for `setReady` (see PA-35). A separate `submittedTargetId` is optional.

**Risk.** View-local state only.

#### PA-38 · Citizen hosts get no night auto-finish and are told to wait while the table waits for their tap

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `Features/Multiplayer/Flow/MultiplayerNightView.swift:663-667`, `Features/Multiplayer/Flow/MultiplayerNightView.swift:679-693`, `Features/Multiplayer/Flow/MultiplayerNightView.swift:342-357`, `Core/Multiplayer/Store/MultiplayerGameStore+HostPhases.swift:77-91`

**Problem.** Auto-finish requires `hasSubmitted` (`guard multiplayerStore.isHost, hasSubmitted, myRole != .inspector, ...`). A citizen host never sets it, because `autoReadyIfPassive` skips hosts (`!multiplayerStore.isHost`, `:683`). Meanwhile their screen says "Citizens have no night action. Wait for morning..." (`:353`) and "Ready to Continue". The only cue that the night is ready is the Finish Night button's colour change.

**Evidence.** The server counts citizens as ready (`convex/lib/rules.ts:81`), so the button enables and nothing deadlocks. The verifier corrected "44–80%": inspector hosts are excluded on purpose, and dead hosts are normally replaced (`rules.ts:223-235`). Citizen hosts are about 22–60% of games, by player count. Not a regression.

**Impact.** In those games the host must tap every night, usually costing a few seconds. No extra calls or renders.

**Solution.** Change the guard to `(hasSubmitted || myRole == .citizen || !isAlive)`, keeping `myRole != .inspector`. Also call `autoFinishNightIfReady()` at the end of `.task` (`:226-229`). Any manual step left needs new copy and a host-only `.sensoryFeedback(.success, trigger: isPhaseReadyToAdvance)`. Don't auto-close voting; the host can still change their vote.

**Risk.** Needs product confirmation. If moved into `runHostAutomation`, add a per-round latch so failures aren't retried every snapshot.

#### PA-39 · Votes and night targets on a seat that left mid-game still count, so that round loses its elimination

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** M

**Location:** `convex/lib/rules.ts:175-184`, `convex/lib/rules.ts:138-143`, `convex/lib/transitions.ts:81-92`, `Features/Multiplayer/Flow/MultiplayerVotingResultsView.swift:26-53`

**Problem.** A non-host can leave in any phase; `removeSeatAndTransferHost` deletes the seat (`transitions.ts:87`). Targets are checked only at submit. `tallyVotes` counts any target id (`counts[v.target_player_id] = (counts[v.target_player_id] ?? 0) + 1`), so the leaver can be the unique leader. `resolveVoteAtomic` then finds no living victim (`convex/voting.ts:70`). At night the kill on a departed target is lost (`convex/night.ts:68-69`).

**Evidence.** Results show "Unknown Player" and "Eliminated: Eliminated Player", then the reveal says "No Elimination – The town couldn't decide". `tests/convex/voting.test.ts:107` (D2) already codifies "removes nobody" for a leave after the reveal. No test covers a leave before `closeVoting` or a departed mafia target.

**Impact.** Rare: the vote leader or mafia target must leave. That round loses its elimination or kill. The win check runs at the next resolve. Nothing stalls.

**Solution.** Filter at resolution: count only ids already in `counts`. Filter night actions to living targets before `majorityTarget`, not inside its loop, because an empty count returns `validTargets[0]` (`rules.ts:110`). Decide on D2 and add vitest cases.

**Risk.** Don't delete actions that target the leaver. BotDirector's per-round `handled` set and the views' local `hasSubmitted` would keep readiness false and stall the round.

#### PA-40 · Host-offline check compares the device clock with server-written heartbeat times

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; failure directions from the verifier's logic simulation, not an app measurement · **Effort:** S

**Location:** `Core/Multiplayer/Store/MultiplayerGameStore+Connection.swift:111-137`, `convex/sessions.ts:153-165`, `convex/lib/util.ts:5`, `convex/lib/rules.ts:222-235`

**Problem.** `last_heartbeat` is server time. `checkHost`/`nextHost` compare it with the device's `Date()` (`:117-118`, `:134`). The server decides staleness by its own clock and accepts a claim only from its chosen successor (`sessions.ts:161`, `HOST_SUCCESSOR`).

**Evidence.** The verifier corrected which skew direction causes the stall. A clock behind by b only delays failover by b. A clock more than about 15 s ahead shows the host as offline for good. If that device is the server's successor and the host drops without leaving, it fails its own freshness filter and never claims. Peers don't claim either, so the game stalls. 10–15 s ahead gives one rejected claim per 5 s.

**Impact.** Rare: it requires "Set Automatically" to be off. It is severe for the affected table.

**Solution.** Simplest fix, with no API change: use the newest human `lastHeartbeat` (your own seat is re-stamped every 5 s) as `serverNow` in both functions. Most robust: change `claimHost` to install the server's successor instead of failing `HOST_SUCCESSOR`. Then drop the client's `nextHost`/`isMe` gate and update `MultiplayerStoreTests.swift:184-195`.

**Risk.** Minimal. Concurrent claims serialize under OCC.

#### PA-41 · Each Clerk token refresh re-authenticates Convex twice, the second time with an identical token

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified through the vendored provider, clerk-ios 1.1.1, convex-swift 0.8.1 and convex-rs sources; hosted-backend behaviour and the template token lifetime not checked · **Effort:** S

**Location:** `Vendor/clerk-convex-swift/Sources/ClerkKitConvex/ClerkConvexAuthProvider.swift:153-175`, `Core/Backend/ConvexService.swift:97-106`, `Core/Auth/Store/AuthStore.swift:75-78`, `Core/Multiplayer/Store/MultiplayerGameStore+Connection.swift:72-79`

**Problem.** On every `.tokenRefreshed`, the listener fetches the "convex" token and pushes it without comparing. That network fetch emits another `.tokenRefreshed`, so an identical second push follows. Each push re-installs the auth callback, and convex-rs sends `Authenticate`. The open-source backend re-runs every subscription on any identity change.

**Evidence.** `ClerkConvexAuthProvider.swift:167-168` `if let token = await Self.refreshedConvexToken(fetch: fetchToken) { onIdToken?(token) }`. `ConvexMobile.swift:339` (convex-swift 0.8.1) calls `setAuthCallback` for every non-nil token. On foreground, `AuthStore.swift:75-78` and `Connection.swift:75` both call `ensureValidSession`, which means two `loginFromCache` calls (`ConvexService.swift:105`). This also happens on inactive→active bounces.

**Impact.** This only affects account users inside a multiplayer session; guests are unaffected. With an assumed 60 s template, it adds about 65–72 avoidable Authenticates per hour, plus up to about 200 cached re-runs and snapshot re-deliveries. That is small next to the heartbeat traffic. A rare token lapse forces a full resubscribe (inferred).

**Solution.** Keep a `lastPushedToken` and push only on change. Also set it from `authenticate()`, clear it on logout, and note the patch in `VENDORED.md`. Fetch with a larger buffer, for example `expirationBuffer: 30`. Coalesce concurrent `ensureValidSession` calls (PA-33). Don't skip `loginFromCache`: revocation detection relies on it throwing. To verify, count `onIdToken` calls for 5 minutes.

**Risk.** Low. A wrongly skipped push recovers through reconnect.

#### PA-42 · `identityRevision` bumps on an unchanged identity and restarts all three multiplayer subscriptions

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `Core/Auth/Store/AuthStore.swift:323-337`, `Core/Auth/Store/AuthStore.swift:363-367`, `Core/Auth/Store/AuthStore.swift:124-135`, `Core/Multiplayer/Store/MultiplayerGameStore+Connection.swift:9-17`

**Problem.** `applyAuthenticatedProfile` always runs `identityRevision += 1` (`:328`), even when `restoreSession` re-applies the same account or guest. The multiplayer observer runs `subscriptions.forEach { $0.start() }` on every new value. `removeDuplicates()` does nothing on a counter that only ever goes up.

**Evidence.** On resume, `ensureValidSession` falls back to `restoreSession` when the token refresh throws or after an earlier failed restore. That leads to a bump, then a cancel and resubscribe (`SubscriptionSupervisor.swift:87-99`). Two resume observers (`AuthStore.swift:75-78`, `Connection.swift:75`) can double it. The verifier found that the sign-in double bump never reaches live subscriptions, and that the brief "not live" state is invisible.

**Impact.** Rare. Each occurrence costs 3, or up to 6, needless resubscribe round trips and re-applied snapshots. No visible effect.

**Solution.** Key the observer on what the subscription arguments actually depend on, the guest proof: `.map { [weak authStore] _ in authStore?.activeGuestProof }.removeDuplicates()`. Skip the debounce idea; network awaits separate the bumps. Remove or coalesce the duplicate resume trigger (also helps PA-41).

**Risk.** Subscriptions must still restart when the proof really changes. Keying on the proof covers exactly those cases.

#### PA-43 · Derived player collections are rebuilt repeatedly per body with linear and O(N²) lookups

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; per-render cost is the verifier's estimate plus one micro-benchmark of mine · **Effort:** S

**Location:** `Core/Multiplayer/Store/MultiplayerGameStore.swift:73-85`, `Features/Multiplayer/Flow/MultiplayerLobbyView.swift:158-197`, `Features/Multiplayer/Flow/MultiplayerNightView.swift:24-58`, `Features/Multiplayer/Flow/MultiplayerVotingResultsView.swift:16-44`

**Problem.** `visiblePlayers` is `players.map(PublicPlayerInfo.init(from:))` on every access (`:77`). `myPlayer` is a linear scan (`:73`) that `myRole`, `isAlive` and `mafiaTeammates` all go through. The lobby reads `visiblePlayers` 7 times per host render (4 for non-hosts) and does 2–3 scans per row. The night and voting filters call `myPlayer` inside `.filter`, which is O(N²), then sort. VotingResults rebuilds `playerLookup` for each row and each vote entry.

**Evidence.** I measured the store's derived-property set at 2.47 µs. The verifier estimates about 10–100 µs per render at N ≤ 19.

**Impact.** Well under 1 ms of CPU per second even at about 3.8 renders/s. This is hygiene; the real lever is the re-render rate (PA-34).

**Solution.** Add a `didSet` on `@Published var players` that recomputes stored `me`, `publicPlayers`, `playersById` (built with `Dictionary(_:uniquingKeysWith:)`) and `mafiaTeammateIds`. Unlike `apply(players:)`, `didSet` also covers `clearLocalSession`; no `@Observable` migration is needed. Bind values once per body, and build the VotingResults lookups outside the `ForEach`. Do this after PA-34.

**Risk.** Very low; local refactor.

#### PA-44 · Outgoing phase views re-render against the new phase payload during their 0.3 s removal transition

**Severity:** Low · **Status:** Needs Further Investigation · **Evidence:** Inferred; code paths code-verified, the removed view's re-render not observed at runtime · **Effort:** S

**Location:** `Features/Multiplayer/Flow/MultiplayerLobbyView.swift:28-71`, `Features/Multiplayer/Flow/MultiplayerNightView.swift:16-22`, `Features/Multiplayer/Flow/MultiplayerVoteDeathRevealView.swift:15-35`, `Features/Multiplayer/Flow/MultiplayerVotingResultsView.swift:8-14`

**Problem.** The router passes `nightIndex` to Morning and DeathReveal. Night, Voting, VotingResults and VoteDeathReveal read `currentSession.currentPhaseData` themselves. During the animated removal (`.animation(.easeInOut(duration: 0.3), ...)`, `:71`), the outgoing view still observes the store and can evaluate against the new phase.

**Evidence.** In that case NightView falls back to `return 1` ("Night 2"), and its `onChange(of: nightIndex)` resets `hasSubmitted`. VoteDeathReveal flips to `noEliminationCard`. The VotingResults list empties.

**Impact.** If confirmed, a 0.3 s flash of wrong content on every device after each vote-out. At night it affects only active roles, on nights other than index 1. No server effect. To confirm, record the simulator with Slow Animations.

**Solution.** Pass the payload from the router as `let` parameters, for example `MultiplayerNightView(nightIndex:)`, and remove the fallbacks. Add `.id(nightIndex)`/`.id(dayIndex)` on the router branches rather than just deleting the reset. After a background resume, a client can jump from `.night(N)` to `.night(N+1)` on the same branch.

**Risk.** Low; previews need new initializers.

#### PA-45 · Tied vote-result rows are ordered differently on each device

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `Features/Multiplayer/Flow/MultiplayerVotingResultsView.swift:20-39`, `Core/Multiplayer/Models/GameSession.swift:153-168`, `convex/lib/rules.ts:175-184`

**Problem.** Rows are sorted by count only (`.sorted(by: { $0.1 > $1.1 })`, `:38`), starting from a `[UUID: Int]` built fresh on each decode (`GameSession.swift:154`). Swift hashing is seeded per process and per instance, and the stable sort keeps that arbitrary order for ties.

**Evidence.** `tallyVotes` gives every living player a count, starting at 0 (`rules.ts:177`), so zero-vote ties appear in nearly every vote. In a tie for first, which is the no-elimination case, each phone can show a different player on top.

**Impact.** Cosmetic. Rows can also reorder on one device after a resubscribe, retry or identity change. It may happen every 5 s if Convex re-sends an unchanged `getSessionView` (unverified). The outcome is decided on the server and is unaffected.

**Solution.** Break ties by `playerNumber`, then by `playerId`:
`.sorted { a, b in a.1 != b.1 ? a.1 > b.1 : (a.0.playerNumber ?? .max, a.0.playerId.uuidString) < (b.0.playerNumber ?? .max, b.0.playerId.uuidString) }`
Optionally do the same in solo `Features/Voting/VoteResultsView.swift:16-24`.

**Risk.** None.

#### PA-46 · Vote reveal schedules its flip sound and haptic with uncancellable `asyncAfter` timers

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `Features/Multiplayer/Flow/MultiplayerVoteDeathRevealView.swift:76-78`, `Features/Multiplayer/Flow/MultiplayerVoteDeathRevealView.swift:264-291`

**Problem.** `.onAppear` starts `DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { triggerCardFlip() }` (`:269`). That plays `AudioServicesPlaySystemSound(1057)` (`:280`) and schedules a second 0.3 s timer for the success haptic (`:287-290`). Nothing ties these timers to the view's lifetime; there is no `.task`, `.onDisappear` or cancellation check.

**Evidence.** The host can't trigger this with Continue, because that button waits for the host's own flip (`:69`). Writing `@State` on a removed view is a no-op.

**Impact.** Rare and cosmetic. It hits a non-host whose reveal arrived late, or a player who leaves, is kicked or sees the game end within about 2.8 s. They hear the flip sound and feel a haptic on the next screen.

**Solution.** Move the sequence into a `.task`: sleep 2.5 s, check `Task.isCancelled`, play the sound and flip, sleep 0.3 s, check again, then fire the haptic. Keep the `revealTriggered` guard. Solo views (`RoleRevealView`, `NightWakeUpView`, `SetupView`) use the same pattern, at lower risk.

**Risk.** None.

#### PA-47 · Voting view does not restore an already-submitted vote after a relaunch and rejoin

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `Features/Multiplayer/Flow/MultiplayerVotingView.swift:5-8`, `Features/Multiplayer/Flow/MultiplayerVotingView.swift:60-127`, `Core/Multiplayer/Store/MultiplayerGameStore.swift:105-109`, `Features/Multiplayer/Flow/MultiplayerNightView.swift:226-232`

**Problem.** The vote-submitted state lives only in view `@State` (`hasSubmitted`, `selectedTargetId`). The night view restores from `myNightAction` (`restoreSubmittedAction`, `:670-677`), but the voting view has no `.task` or `.onChange` restore, and the store has no `myVote`.

**Evidence.** The voter can always see their own vote row (`convex/lib/projections.ts:112`). Re-voting is an upsert (`convex/play.ts:84-85`).

**Impact.** Rare and cosmetic. It only happens after a relaunch and rejoin with the room code while voting is still open; network reconnects don't re-mount the view. The player sees an empty ballot. The round still completes, because `votesReady` counts vote rows. The host loses only the highlight.

**Solution.** Add `myVote` to the store next to `myNightAction`. Add `restoreSubmittedVote()`, called from `.task` and `.onChange(of: multiplayerStore.myVote?.id)`. It should always set `selectedTargetId`, but set `hasSubmitted` only for non-hosts so the host keeps silent re-voting. Add a store unit test with a `RoundState` fixture.

**Risk.** Negligible; about 15 client-only lines.

#### PA-48 · Resume can restart the heartbeat loop after the session was cleared during the token refresh

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `Core/Multiplayer/Store/MultiplayerGameStore+Connection.swift:72-79`, `Core/Multiplayer/Store/MultiplayerGameStore+Connection.swift:90-98`, `Core/Multiplayer/Store/MultiplayerGameStore+Connection.swift:100-101`, `Core/Multiplayer/Store/MultiplayerGameStore.swift:212-217`

**Problem.** `handleAppResume` checks `sessionId != nil`, then awaits `ensureValidSession()`. After the await it re-checks only `isInBackground` before calling `startTicking()`. If the session is cleared during the await, a tick loop starts with no session. The most likely cause is a kicked or cancelled snapshot that arrives after reconnect.

**Evidence.** The sequence is at Connection.swift:74-78. The await only suspends for Clerk accounts or after a restore that failed transiently (`AuthStore.swift:124-135`), so guests are not exposed. The verifier refuted the leak claim. The `let self` binding lasts one iteration, so deinit is delayed by at most one tick plus the 5 s sleep.

**Impact.** Negligible. The loop wakes the MainActor every 5 s and does nothing, because `tick()` returns at `guard let sessionId`. It runs until the next background transition or the next create or join. There is no leak and no extra heartbeat.

**Solution.** Change Connection.swift:76 to `guard sessionId != nil, !isInBackground else { return }`. Optionally, let the loop end itself with `guard await self?.tickIfActive() == true else { return }`. Do not use the auditor's `guard let self` rewrite, because it still holds `self` across the sleep.

**Risk.** None meaningful.

#### PA-49 · Create/join discards the returned room code and pushes a bare spinner, with a possible torn 0-player frame

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; the torn frame is inferred · **Effort:** S

**Location:** `Core/Multiplayer/Store/MultiplayerGameStore.swift:165-172`, `Features/Multiplayer/Flow/MultiplayerLobbyView.swift:72-74`, `Features/Multiplayer/Flow/MultiplayerLobbyView.swift:245-251`, `convex/sessions.ts:14-16`

**Problem.** `createSession` and `joinSession` return `room_code`, but `enter()` keeps only `sessionId`. Until the first `getSessionView` value arrives, the lobby shows only an unlabeled `ProgressView()`. The session view and the players are applied separately, so the host can briefly see "Players (0/19)" and the red "Need 4-19 total players to start".

**Evidence.** The relevant lines are MultiplayerGameStore.swift:167-169, sessions.ts:15, and MultiplayerLobbyView.swift:73 and :247-250. The torn frame needs the first values to land in different runloop passes (inferred).

**Impact.** Cosmetic. The wait is one subscription round trip: 42 ms RTT was measured, plus 10–17 ms of query time from dev logs. The ~350 ms push animation mostly hides it, but on cellular the content may visibly pop in. Users who join already typed the code.

**Solution.** Store `result.roomCode` and clear it in `clearLocalSession`. Show the code with "Connecting…" in the loading branch, and keep showing it while `players.isEmpty`. Returning snapshots from the mutations would need an api_contract bump, which is not worth it here.

**Risk.** Very low; client-only.

#### PA-50 · A reused mafia-bot target is never re-validated, so a mid-night leave can stall the night until End Game

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; frequency inferred · **Effort:** S

**Location:** `Core/Multiplayer/Store/BotDirector.swift:149-158`, `Core/Multiplayer/Store/BotDirector.swift:77-100`, `convex/lib/rules.ts:216-217`, `convex/lib/rules.ts:77-92`

**Problem.** When no human mafia is alive, pending mafia bots reuse the latest mafia row's `targetPlayerId` without calling `canTarget`. The human-follow branch at :145 does call it. The failure starts when that target's seat is deleted while a bot is still pending, for example when a non-host human taps Leave Game. Every re-plan then sends the dead target again. TARGET_DEAD does not close the round, so the bot retries on every snapshot. `nightActionsReady` never becomes true.

**Evidence.** The reuse is at BotDirector.swift:151-153. On error, :87 returns false and :70 calls `handled.remove(key)`. The server rejects at rules.ts:217 with `fail(E.TARGET_DEAD)`. The stale row persists, so a relaunch or a host transfer plans the same target again.

**Impact.** Rare. It needs 2+ mafia bots, no human mafia, and the target leaving within the tens of ms between bot mutations. When it happens, the game is stuck until End Game.

**Solution.** Validate the reused target: `?.targetPlayerId.flatMap { canTarget($0, actor: pending[0], role: .mafia, alive: alive) ? $0 : nil } ?? coordinated`. The `flatMap` matters because `canTarget(nil)` is true. Add a test. With 2 bots this alone loses the kill, because the 1–1 tie goes to the stale row. Also ignore rows whose target is no longer a living seat in `buildNightRecord` (rules.ts:138-143).

**Risk.** Low; covered by the new tests.

#### PA-51 · Bot vote fallback fires on any non-closing error and picks a role-blind random seat

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; transport-error path inferred · **Effort:** S

**Location:** `Core/Multiplayer/Store/BotDirector.swift:83-99`, `Core/Multiplayer/Store/BotDirector.swift:63`, `Core/Gameplay/Services/BotDecisionService.swift:127-145`

**Problem.** After any vote error that does not close the round, `submit` immediately votes again for `alive.filter { ... }.randomElement()`. `alive` is a `[UUID]` with no roles, so a mafia bot can vote out a teammate. That breaks the `nonMafiaTargets` rule in `chooseVotingTarget`. Actor-side errors (HOST_ONLY, ACTOR_DEAD, NOT_MEMBER) make the fallback fail too.

**Evidence.** BotDirector.swift:87 has `guard plan.actionType == .vote else { return false }`, and the fallback is at :90. The only test (BotDirectorTests.swift:242) uses a citizen bot. Whether transport errors reach this path depends on convex-swift behaviour that was not verified.

**Impact.** Very small. A teammate vote needs a player to leave within about one round trip, and then an unlucky random pick. Actor-side errors cost about one extra failed mutation per bot.

**Solution.** Delete the fallback block (:87-99) and return false for every non-closing error. The next snapshot then re-plans through `chooseVotingTarget`, with role rules and fresh players. Update the test and add a mafia case.

**Risk.** Negligible; host-only bot code.

### 4.5 Low severity · Startup, auth and library screens

#### PA-52 · Cold-start restore sends a redundant Clerk refresh for guests and writes the user row on every launch

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Code-verified; latency inferred · **Effort:** M

**Location:** `Core/Auth/Services/AuthService.swift:29-37`, `Core/Auth/Store/AuthStore.swift:89-118`, `convex/users.ts:27-35`, `convex/users.ts:93-97`

**Problem.** For guests and signed-out users `Clerk.shared.user == nil`. `currentUser` therefore awaits its own `refreshClient()`, even though `Clerk.configure` has already started the same request. Guest restore and the Online card wait on it. `ensureUser` and `createOrRestoreGuest` also patch the user row on every launch.

**Evidence.** The refresh is at AuthService.swift:31-33. On a throw, AuthStore.swift:92-98 returns before the guest branch. users.ts:33 and :95 always call `ctx.db.patch`. The verifier made three corrections:
- Accounts load the cached client synchronously, so they skip both `refreshClient` and the 5 s poll.
- `loginFromCache` adds no extra token request.
- The per-launch write invalidates no live subscription.

**Impact.** Guests wait about one extra Clerk HTTPS round trip. The Clerk request was not measured, but a cold HTTPS call to Convex measured p50 282 ms. On a stalled network the wait can reach the 60 s URLSession default. Local play is unaffected. With 330 dev users, one write per launch is negligible.

**Solution.** In `currentUser`, return nil when `Clerk.shared.user == nil` instead of refreshing. Upgrade the identity on Clerk's `.sessionChanged` event. Do not wait on `isLoaded`, which can hang. Do not restore guests in parallel either, because that breaks `AccountRestorationTests.swift:59-70`. Optionally, skip patches that change nothing.

**Risk.** Low to medium. The restore order changes, and it must keep the Online gating from FOLLOWUP-14.

#### PA-53 · Library screens refetch with a full-screen spinner on every visit and after every edit

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `Features/Stats/CustomRolesView.swift:17-39`, `Features/Stats/PlayerGroupsView.swift:17-39`, `Core/Backend/DatabaseService.swift:62`, `Features/Setup/SetupView.swift:425-456`

**Problem.** The three library screens reload on every push through a one-shot `query()`. While `isLoading` is set, the whole ScrollView is replaced by a ProgressView, even during pull-to-refresh. Create and update discard the returned row and query the whole list again. The Setup sheets keep their data in `@State` but hide it behind the spinner.

**Evidence.** The spinner is at CustomRolesView.swift:17, and the reloads are at :53-60 and :102-104. DatabaseService.swift:62, 72, 97 and 107 discard results with `let _: ...`. The verifier corrected one point: add and edit reload behind the still-open sheet, where Save stays disabled for two round trips. Only delete visibly flashes the list, and the scroll position resets.

**Impact.** Polish only. Each open shows about one round trip of spinner: 42 ms RTT was measured, plus 10–17 ms of query time. The lists are tiny: dev holds 6 configs and 3 groups across all users.

**Solution.** In all five places, show the spinner only when `isLoading && items.isEmpty`. Return the decoded row from `DatabaseService.create*/update*` and insert or replace it locally. On delete, use `removeAll`. Dismiss the sheet on success. A global LibraryStore is more than this needs.

**Risk.** Low.

#### PA-54 · Player Stats and the Setup load sheets show empty states when a load fails

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `Features/Stats/PlayerStatsView.swift:7`, `Features/Stats/PlayerStatsView.swift:41-54`, `Features/Setup/SetupView.swift:492-505`, `Features/Setup/SetupView.swift:535-548`

**Problem.** `PlayerStatsView` stores `errorMessage` but never renders it. A failed load therefore shows "No Stats Yet — Complete some games…". FOLLOWUP-16 fixed the same defect in Custom Roles and Player Groups but missed Stats. The Setup sheets catch errors ("Silent fail") and replace already-loaded data with `[]`.

**Evidence.** The body branches only on `isLoading` and `isEmpty` (PlayerStatsView.swift:15-19). The catch at :49-51 sets `errorMessage`, which nothing reads. SetupView.swift:501 and :544 assign `[]`. The verifier corrected the trigger. Offline, `ConvexService.query` never completes, so the user sees an endless spinner. The empty state appears only for server-reported errors: E.AUTH, a function missing during deploy skew, or a decode mismatch.

**Impact.** Rare and cosmetic, but it reads like data loss. Pull-to-refresh recovers.

**Solution.** In PlayerStatsView, check `errorMessage` before the empty branch and show an inline error with Retry. Prefer this to an alert, which leaves "No Stats Yet" on screen. Keep old data when a load fails. Pass an error into the two Setup sheets and stop assigning `[]`. The offline spinner needs a first-value timeout and a cancellation handler in `ConvexService.query`, which is a separate fix (PA-08).

**Risk.** Minimal.

#### PA-55 · Sound warm-up builds four AVAudioPlayers on the main thread before the first frame of every launch

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Measured (Time Profiler, second pass) · **Effort:** S

**Location:** `App/mafia_managerApp.swift:32-35`, `Core/Gameplay/Services/SoundManager.swift:24-41`, `Core/Gameplay/Services/SoundManager.swift:71-73`

**Problem.** `RootView.onAppear` calls `SoundManager.shared.warmUp()`. That creates four `AVAudioPlayer(contentsOf:)` instances and calls `prepareToPlay()` on the MainActor before the first frame. Only the solo night and morning screens play these sounds; multiplayer never does.

**Evidence.** Code-verified: SoundManager.swift:28-40. docs/SESSION_CHANGES.md records 84 ms+ for `AVAudioPlayer` init at the old play sites. I measured the following:
- Launch to responsive took 2.752 s against 2.469 s for a bare SwiftUI app, about 0.3–0.4 s more. Most of that gap is the system loader (PA-101).
- The Intro screen runs 15 threads against the control's 4, including `AQConverterThread`.
- The `.wav` files are AAC in M4A.

In the second pass, Time Profiler covered three foreground launches on the Xcode 27.0 release:
- `SoundManager.warmUp()` takes **48–54 ms** of main-thread time in the root view's `onAppear`, including 17–20 ms in `AVAudioPlayer.init(contentsOf:)`.
- That is about 75% of the app's own launch work, which totals 64–69 ms.
- For comparison, the eager Convex client costs 6–7 ms and Clerk set-up 7–8 ms (§3.8).

The auditor's lazy `databaseService` idea is dropped, because `AuthStore.init` creates the Convex client anyway.

**Impact.** About 50 ms of main-thread time per cold launch, measured on the simulator. Slower phones will take longer, and multiplayer users get nothing from it.

**Solution.** Remove the call from `onAppear`. Warm up from the Start Night action (NightWakeUpView.swift:176) and keep the fallback in `play()`. Skip `Task.detached` for building the players. PA-72 covers the audio-session category and re-activation.

**Risk.** Low.

#### PA-56 · Missing or wrong backend config fails only at launch since the build-time guard was removed

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; the entitlement effect is inferred · **Effort:** S

**Location:** `Core/Backend/ConvexConfig.swift:9-25`, `Project.swift:30-31`, `Project.swift:59`

**Problem.** Info.plist values come from xcconfig substitution. If a key is missing or misspelled, the build still succeeds, and the app hits `fatalError` at the first `ConvexService.shared` access during `AuthStore` init. Commit d0b8e29 (2026-10-10) removed the pre-build guard, which also checked more than presence. Some Release mistakes now ship silently:
- A Release build pointed at the dev Convex host runs against dev data.
- A wrong `MAFIA_CLERK_FRONTEND_HOST` breaks only the associated-domains entitlement (inferred).

**Evidence.** ConvexConfig.swift:20-23 calls `fatalError("Missing \(key) in Info.plist...")`. Lines :11-14 check for `pk_live_` only under `#if !DEBUG`. docs/SESSION_CHANGES.md:21 says "A missing xcconfig value crashes at launch rather than failing the build." There is no CI.

**Impact.** The likelihood is low, because both xcconfigs are tracked and correct today. If it happens, every launch of that build crashes, and only a manual launch catches it.

**Solution.** Add an inline `.pre(script:, name: "Verify backend config", basedOnDependencyAnalysis: false)` that requires all three `MAFIA_*` values. In Release, use POSIX `case` to require `pk_live_*`, a non-dev `.convex.cloud` host and a non-`.accounts.dev` frontend host. Keep the runtime check.

**Risk.** Very low; a few ms per build.

#### PA-101 · AuthenticationServices, pulled in by ClerkKit, makes the app load about 1,000 extra system libraries at launch

**Severity:** Low · **Status:** Needs Further Investigation · **Evidence:** Measured on the simulator (Time Profiler, App Launch template, `DYLD_PRINT_LIBRARIES`); device impact not measured · **Effort:** S to measure, L to change

**Location:** `Project.swift` (the `ClerkKit` dependency); clerk-ios `Sources/ClerkKit/Domains/Auth/SignIn/SignInService.swift`, `SignUp/SignUpService.swift`, `SignUp/SignUp.swift` (`import AuthenticationServices`). The app's own sources do not import it.

**Problem.** At launch the app loads **1,603** system images, against **596** for an empty SwiftUI app. The extra ~1,000 include ARKit, CarPlay, MapKit, WebKit, Charts, EventKit, ContactsUI, AVKit and the AppIntents cross-import overlays, none of which the game uses. A one-line probe isolates the cause. Adding `import AuthenticationServices` to the empty app raises its count to 1,597. Adding WatchConnectivity, CryptoKit, AVFAudio or Combine adds 0–1 images each.

**Evidence.** Measured on the iOS 27.0 simulator with Xcode 27.0 (27A266a), Release builds:
- **Loader CPU per launch** (Time Profiler, `dyld_sim` self time): app 1,325–1,688 ms; empty app 448–596 ms; empty app plus AuthenticationServices 1,535–1,698 ms.
- **Loader wall time** (App Launch template, `Launch Executable` interval): app 1,867–2,930 ms; empty app plus AuthenticationServices 1,949–2,753 ms; empty app 698–1,049 ms.
- **The app's own code is small by comparison:**
  - In three foreground launches, main-thread samples inside app code total 64–69 ms (PA-55 itemises them).
  - Static initializers total 52.6 ms in the app and 51.2 ms in the empty app.
- **Not the symbol table:** a stripped copy (`__LINKEDIT` 0.67 MB instead of 11.8 MB) still spends 1,519–2,022 ms in the loader.
- The hot loader code is `mach_o::Header::forEachLoadCommand`, `stringFromOffsetInLoadCommand` and `strcmp`, symbolicated with `atos` against `dyld_sim`. That is per-image load-command work, which scales with the number of images.

**Impact.** On the simulator, every launch spends about 1 s of extra loader CPU and 1–2 s of extra wall time before `main`. That is a development-loop cost: every run, UI test and test-host boot (PA-92) pays it. On a device, libraries in the dyld shared cache load much more cheaply, so the user-facing cost is probably far smaller. **It was not measured.**

**Solution.**
1. Measure on a physical iPhone with the App Launch template before doing anything.
2. If the device cost is material, the only lever is to keep AuthenticationServices off the launch path. Clerk links it statically for Sign in with Apple and passkeys, so that would mean upstream work or a lazily loaded auth module. That is not worth doing for a simulator-only cost.

**Risk.** None to measure. Restructuring Clerk loading would be a large change with auth regression risk.

### 4.6 Low severity · Solo game and shared UI

#### PA-57 · Solo stats sync writes bot seats ("Bot 1"…"Bot N") as player_stats rows

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Code-verified; row volume inferred · **Effort:** S

**Location:** `Core/Gameplay/Store/GameStore.swift:709-726`, `Core/Gameplay/Store/GameStore.swift:97-104`, `Core/Gameplay/Store/GameStore.swift:185-192`, `convex/stats.ts:121-158`

**Problem.** `syncPlayerStatsToCloud` loops over every player with no `isBot` filter. Bots are named "Bot 1"…"Bot N", and `upsertPlayerStat` keys rows by user and name. Each slot number therefore becomes one merged stats row on the Player Stats screen. Each bot also adds one more mutation to the sequential sync (PA-04).

**Evidence.** Bot names come from GameStore.swift:100 `(1...numberOfBots).map { "Bot \($0)" }`. The loop at :710 is `for player in state.players {`. Guests reach this path too. The Supabase-era export had 0 bot rows out of 48. I counted 58 `player_stats` rows on dev, but not how many of them are bots.

**Impact.** Bounded: at most about 19 "Bot N" rows per user. A finished game makes up to 18–19 extra background mutations, with no UI stall. The result is clutter, not a performance problem.

**Solution.** Use `for player in state.players where !player.isBot {`, or drop bots when building a batched payload. Add a unit test. A server-side reject and a cleanup migration are optional, and only needed if real data has these rows.

**Risk.** None, unless bot stats were intended as a product feature.

#### PA-58 · Solo night timers and bot turns are not cancelled and can change an abandoned game after End Game

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** M

**Location:** `Features/Night/NightWakeUpView.swift:811-820`, `Features/Night/NightWakeUpView.swift:889-910`, `Core/Gameplay/Store/GameStore.swift:556-654`, `Core/Gameplay/Services/BotDecisionService.swift:173-178`

**Problem.** The night runs on `asyncAfter` closures and an unstored `Task`, and `simulateThinking` uses `try? await Task.sleep`. Nothing cancels them, and `endNight` and `resolveNightOutcome` have no `isGameOver` guard. End Game can be confirmed during the doctor's 2 s transition or a bot's 3.5–5.5 s turn. The pending work then still records a night action or kills the target, and saves.

**Evidence.** The doctor path at NightWakeUpView.swift:811-819 calls `resolveNightOutcome`, and bot turns call `endNight` at :944, :973 and :1002. `endGameEarly` (GameStore.swift:764) cancels nothing. The mafia and inspector closures are phase-guarded and safe. A related problem uses the same pattern: with all-bot mafia, auto-continue (:857-876) can start the night without waiting for Start Night (PA-14).

**Impact.** Rare and cosmetic: a phantom death in the abandoned game's log, and no stats sync. The auto-continue problem is assessed in PA-14.

**Solution.** Add `guard !state.isGameOver else { return }` at the start of `endNight` and `resolveNightOutcome`. Do not add a night-phase guard yet, because the doctor paths call `completeRoleAction` before resolving. Move bot turns to `.task(id: store.state.currentPhase)` and start mafia auto-continue from the Start Night action.

**Risk.** Low; keep the delays and add tests.

#### PA-59 · Setup player rows use index identity, so deleting a row animates the wrong row and can misplace focus

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Code-verified; crash not reproduced · **Effort:** M

**Location:** `Features/Setup/SetupView.swift:63-88`, `Features/Setup/SetupView.swift:104-120`, `Features/Setup/SetupView.swift:130-134`, `Features/Stats/PlayerGroupsView.swift:286`

**Problem.** The rows use `ForEach(names.indices, id: \.self)` with a hand-made index `Binding`. Removing row k deletes the row with id n-1, and the text of the rows below changes in place. `.onMove` moves the values while the ids stay put. Neither closure checks bounds.

**Evidence.** The index binding is at SetupView.swift:82-87 (`Binding(get: { names[idx] }, ...)`), and :108 calls `names.remove(at:)`. PlayerGroupsView.swift:286 and :454 use the same pattern. Typing in the last row is the common case; deleting another row then removes the focused field rather than moving focus. An out-of-range crash is possible but not reproduced (PA-66).

**Impact.** This is the first screen of every solo game. The wrong row animates out, drag can snap, and sometimes the user types into another player's field. No data is lost.

**Solution.** Use `struct PlayerEntry: Identifiable { let id = UUID(); var name: String }` with `ForEach($entries)` and remove rows by id. Keep the 30-character clamp, and key `@FocusState` by entry id. Map back to `[String]` where needed, and fix PlayerGroupsView the same way. Raise this to Medium if the crash is reproduced.

**Risk.** Low.

#### PA-60 · About 650 lines of unreachable legacy solo views and several dead APIs are still compiled

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; build warnings measured · **Effort:** S

**Location:** `Features/Assignments/AssignmentsView.swift:3-241`, `Features/Night/NightPhaseView.swift:3-185`, `Features/Night/NightOutcomeView.swift:3-222`, `Core/Gameplay/Store/GameStore.swift:658-677`

**Problem.** Nothing creates `AssignmentsView`. It is the only way into `NightPhaseView`, which is the only way into `NightOutcomeView`, so 648 lines are unreachable. Other dead code:
- `PhaseCard` and `PillButtonStyle`.
- Four GameStore APIs, five query helpers and six InputValidator validators.
- NightAction's `*PhaseCompleted` fields.
`docs/ARCHITECTURE_NOTES.md:18` still describes NightPhaseView as live.

**Evidence.** The routing at `App/mafia_managerApp.swift:88-108` never reaches these views. Measured: the Debug build warns about the deprecated `NavigationLink(destination:isActive:)` at AssignmentsView:46, NightPhaseView:68 and NightOutcomeView:72 (see PA-91). `applyDayRemovals` is used only by tests: five call sites in SoloVoteValidationTests and GameStoreTests.

**Impact.** No runtime cost. The risk is that someone edits the dead UI by mistake, and the files add build warnings.

**Solution.** Delete the dead code, but keep `aliveNonMafia` and `alivePlayersWithRole`. Old saves still decode without the removed fields. Update ARCHITECTURE_NOTES.md:11 and :18. Rewrite the five `applyDayRemovals` call sites, or keep the method under `#if DEBUG`.

**Risk.** Low; Tuist picks up the deleted files.

#### PA-61 · RootView observes an AuthStore it never reads, and NightWakeUpView holds a class-typed service field

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `App/mafia_managerApp.swift:58`, `Features/Night/NightWakeUpView.swift:17`, `Core/Gameplay/Services/BotDecisionService.swift:4-5`, `Core/Gameplay/Store/GameStore.swift:7-19`

**Problem.** `RootView` declares `@EnvironmentObject private var authStore: AuthStore`, but neither `body` nor `phaseBasedView` reads it. Every AuthStore publish therefore re-evaluates RootView. `NightWakeUpView` stores `private let botService = BotDecisionService()`, which is a stateless `final class`. The view never compares equal, so its body re-runs on those passes.

**Evidence.** The declaration is at mafia_managerApp.swift:58, and BotDecisionService.swift:5 reads `final class BotDecisionService {`. The verifier corrected three points. The five writes in `applyAuthenticatedProfile` coalesce into one render. A guest's foreground `ensureValidSession` publishes nothing. GameStore's coarse publishing coalesces per action, and `save()` is debounced.

**Impact.** Negligible: about 1–3 extra RootView passes at launch, plus one per identity change. It is listed so that an `@Observable` migration is not over-prioritized.

**Solution.** Delete line 58; child views get AuthStore from the App's `.environmentObject` at :29. Make `BotDecisionService` a struct, or an enum with static functions. Defer any `@Observable` migration.

**Risk.** None.

#### PA-62 · Nested NavigationStack on the mode-selection screen, with deprecated hidden links carrying the screen's modifiers

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; deprecation warnings measured (PA-91), runtime effects inferred · **Effort:** M

**Location:** `App/mafia_managerApp.swift:62-78`, `Features/Multiplayer/Entry/GameModeSelectionView.swift:20-175`, `Features/Multiplayer/Entry/GameModeSelectionView.swift:117-174`, `Core/Gameplay/Store/GameStore.swift:64,78`

**Problem.** RootView's `NavigationStack` has `GameModeSelectionView` as its root, and that view opens a second `NavigationStack`. Inside it, two hidden `NavigationLink(destination:isActive:)` links with `EmptyView` labels sit next to `.navigationDestination(for: GameMode.self)`. Because the second link comes right before the modifier chain, `.navigationDestination`, `.toolbar`, three `.sheet`s and `.onAppear` are attached to that zero-size link instead of the ZStack. Commit ce4ecaec introduced this by accident.

**Evidence.** `GameModeSelectionView.swift:124` `NavigationLink(destination: SetupView(), isActive: $autoNavigateLocal) { EmptyView() }` is followed directly by `:129 .navigationDestination(...)`. The clean Debug build warns about the deprecated links at :118 and :124 (measured). VoiceOver exposes the hidden links as unnamed buttons, as `docs/AUDIT_FINDINGS_2026-04-25.md` already noted. There is no performance cost.

**Impact.** The risk is latent: navigation could break silently on a future OS update or a small edit, and VoiceOver users hear extra buttons today. Inferred, needs a simulator check: `returnToSoloSetup` is never cleared by the `.onAppear` (:170). After Play Again, tapping Back may push SetupView again.

**Solution.** Remove the inner stack. Keep RootView's, because the solo phase toolbars need it. Replace both hidden links with `.navigationDestination(isPresented:)`, move the modifiers back onto the ZStack, and clear `returnToSoloSetup` once it has been used.

**Risk.** Navigation regressions. Re-test Play Again → Back, the guest sign-in auto-push → Back, and the gear toolbar and sheets.

#### PA-63 · Sound assets are AAC audio in M4A containers but named `.wav`

**Severity:** Low · **Status:** Recommended · **Evidence:** Measured (`afinfo`, `file`, `xxd`) · **Effort:** S

**Location:** `Core/Gameplay/Services/SoundManager.swift:29-30`, `Core/Gameplay/Services/SoundManager.swift:34`, `Resources/Sounds/`

**Problem.** All four files in `Resources/Sounds/` contain AAC audio in an M4A container but have a `.wav` extension. `SoundManager` loads them with `withExtension: "wav"` and opens them with `AVAudioPlayer(contentsOf:)`. That player reads the file content to find the format, so playback works.

**Evidence.** Measured with `afinfo`: every file reports `File type ID: m4af` and `2 ch, 48000 Hz, aac`. Durations are 1.80–2.03 s, sizes are 57,630–72,932 bytes (265 KB in total), and each header is `ftypM4A`. `SoundManager.swift:29` calls `Bundle.main.url(forResource: sound.rawValue, withExtension: "wav")`.

**Impact.** None today, and decoding cost is negligible. The risk is latent. A future switch to an API that needs real PCM WAV (`AudioServicesCreateSystemSoundID`, `UNNotificationSound`) would fail at runtime, and SoundManager would only print a log line. No current build tool reads the extension.

**Solution.** In one commit, `git mv` the files to `.m4a`, update `withExtension:` and the log string at :29-30, and run `tuist generate` (`Resources/**` is globbed). Add a unit test that every `GameSound.allCases` file resolves to a URL and opens in `AVAudioPlayer`.

**Risk.** Very low. If the rename is incomplete, SoundManager only logs and the sound stays silent; the test catches this.

#### PA-64 · Intro screen CTA buttons overflow their fixed 56 pt row at large text, and the pager height can go negative

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; negative-height warnings and VoiceOver reach inferred · **Effort:** S

**Location:** `Features/Intro/IntroView.swift:36-55`, `Features/Intro/IntroView.swift:128`, `Core/UI/DesignSystem.swift:186-193`

**Problem.** IntroView builds all five pages in a plain `HStack`, moves between them with `.offset`, and sizes the pager as `geometry.size.height - 200` with no clamp (:53). The button row is fixed with `.frame(height: 56)` (:128). `CTAButtonStyle` scales button height with Dynamic Type (`@ScaledMetric`, `DesignSystem.swift:186`), so at large text sizes the buttons grow taller than the row.

**Evidence.** Code-verified: a button is about 76 pt at xxxLarge and about 109 pt at AX1, where it covers the page indicator. The height goes negative only on a layout pass that offers less than 200 pt, such as the zero-size pass while the view is being presented. The 2026-04-25 audit saw "Invalid frame dimension" warnings; the verifier could not reproduce them.

**Impact.** Buttons overlap other content for users with large text. The screen appears once per install and when reopened from Settings. Performance cost is negligible.

**Solution.** Smallest fix: `max(0, geometry.size.height - 200)`, and `.frame(minHeight: 56)` at :128. Better: a horizontal `ScrollView` with `LazyHStack`, `.scrollTargetBehavior(.paging)` and `.frame(maxHeight: .infinity)`. Avoid `TabView(.page)`; it was removed twice before for sizing problems (66ce453, 11efb2f).

**Risk.** Low. Keep the `intro_*_button` IDs, and check that VoiceOver no longer reaches offscreen pages.

#### PA-65 · `Persistence.reset()` leaves the pending debounced save running, and backgrounding writes the state twice

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; write cost measured · **Effort:** S

**Location:** `Core/Gameplay/Services/Persistence.swift:33-64`, `Core/Gameplay/Services/Persistence.swift:80-82`, `App/mafia_managerApp.swift:38-44`, `Core/Gameplay/Store/GameStore.swift:62-65`

**Problem.** `save()` schedules a write that runs 300 ms later. `reset()` deletes the file but does not cancel that pending write, so the game that was just reset can be written back. The scene-phase handler also calls `saveImmediately` on both `.inactive` and `.background`. A home swipe therefore writes the state twice, even when the state is unchanged or empty.

**Evidence.** `Persistence.swift:80-82` is `func reset() { try? FileManager.default.removeItem(at: stateURL) }`. `mafia_managerApp.swift:38-40` is `case .background, .inactive: try? Persistence.shared.saveImmediately(...)`. Measured for a 19-player state: `saveImmediately` takes 415 µs, encoding takes 47.7 µs, and load takes 128 µs.

**Impact.** Main-thread cost is negligible; the measured numbers replace the earlier 1–6 ms estimates. The race needs Play Again (the only live `resetAll` caller) within 300 ms, followed by a kill before the next save. Its only effect is the old Game Over screen on relaunch.

**Solution.** Call `saveTask?.cancel(); saveTask = nil` in `reset()` and `saveImmediately`. Optionally skip a write when the state has not changed since the last one, but keep the compact `.inactive` save, because a kill from the app switcher may not deliver `.background` (PA-05). Keep the sound and multiplayer `.inactive` handling unchanged here. An actor is not justified at the measured cost. Make the class injectable and add tests.

**Risk.** Low, as long as `.background` still writes synchronously.

#### PA-66 · Player name editors bind `TextField`s by array index and remove rows in place (Player Groups and solo Setup)

**Severity:** Low · **Status:** Needs Further Investigation · **Evidence:** Inferred (crash); index-based row identity code-verified · **Effort:** S

**Location:** `Features/Stats/PlayerGroupsView.swift:286-307`, `Features/Stats/PlayerGroupsView.swift:454-475`, `Features/Setup/SetupView.swift:64-133`

**Problem.** Both group editors use `ForEach(playerNames.indices, id: \.self)` with `TextField(text: $playerNames[index])`, and each row's minus button calls `playerNames.remove(at: index)`. Removing the focused last row can leave SwiftUI reading a binding to an index that no longer exists. This is a widely reported "Index out of range" crash pattern. Because rows are identified by position, removing a middle row also leaves focus on that screen position, not on the name. Solo `SetupView` uses the same pattern inside a `List` with animated removal; its wrong-row animation and focus effects are PA-59.

**Evidence.** Code-verified at `PlayerGroupsView.swift:286`, :288 and :300. Nothing ends editing before a row is removed. The crash has not been reproduced. To check: a UI test that adds 6 rows, focuses the last one and taps its minus button, in both editors.

**Impact.** A possible crash that loses an unsaved group draft. SetupView matters more because every solo game goes through it.

**Solution.** Give each row an `id`, use `ForEach($rows) { $row in ... }`, and remove rows by id. Do not use `enumerated()` with `$rows[offset]`.

**Risk.** Small refactor. Keep the automation IDs unchanged.

#### PA-67 · Shadows are drawn from whole composite views, and the button styles stack two shadows

**Severity:** Low · **Status:** Needs Further Investigation · **Evidence:** Inferred; shadow placement code-verified · **Effort:** S

**Location:** `Core/UI/DesignSystem.swift:150`, `Core/UI/DesignSystem.swift:224-225`, `Core/UI/DesignSystem.swift:311-312`, `Features/Setup/SetupView.swift:203`

**Problem.** `Card` applies its shadow after the background and overlay, so the shadow is drawn from all of the card's content. In SetupView (:203) that content includes a UIKit-backed `List` of text fields. The CTA and Grid button styles stack two shadows. The SetupView bottom bar adds a third shadow (:423), and the GameOver banners nest shadowed layers.

**Evidence.** Placement is code-verified, and the code never shadows only the background shape. Corrections: `Card` applies one shadow, not two, and `PillButtonStyle` is unused. `AssignmentsView`, which the verifier called the worst instance, is never instantiated (confirmed by grep).

**Impact.** Not measured; likely well under 1 ms per frame on A15 and newer devices. Possible extra offscreen rendering passes while SetupView rows animate, scroll or are typed into. To check: the Simulator's "Color Off-screen Rendered" option and an Instruments hitches trace.

**Solution.** Draw each shadow from the background shape only, for example `.background(RoundedRectangle(...).fill(...).shadow(...))`. Merge stacked shadows, and move the bottom-bar shadow onto the bar's background. Do not use `.drawingGroup()` around the UIKit `List`.

**Risk.** Shadows look slightly different, so the change needs a design review.

#### PA-68 · Material blur is drawn over content that has already been removed (night transition and role-reveal screens)

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `Features/Night/NightWakeUpView.swift:20-38`, `Features/Night/NightWakeUpView.swift:1122-1127`, `Core/Components/PrivacyBlurView.swift:7-11`, `Features/Assignments/RoleRevealView.swift:10-20`

**Problem.** `TransitionBlurView` and `PrivacyBlurView` fill the screen with `.ultraThinMaterial`. They are shown in an `if/else` branch that removes the real content, so only the opaque `surface0` background is behind the blur. The privacy comes from removing the content, not from the blur. A third use is at `NightWakeUpView.swift:105-106`.

**Evidence.** `NightWakeUpView.swift:1126` is `.fill(.ultraThinMaterial)`. `RoleRevealView.swift:14-15` is `if showBlur { PrivacyBlurView() } else { mainContent }`. Both overlays are static.

**Impact.** GPU cost is negligible: the blur is recomputed only during each 0.3 s fade, not while the screen holds. The original claim of a sustained cost was overstated. The real problem is clarity: the names suggest the blur provides privacy.

**Solution.** Use an opaque fill such as `surface1`, or delete the `Rectangle`, and rename the views. Do not keep content mounted under `.blur(radius:)`; that leaves the secret in the view tree.

**Risk.** Minimal: a slight change in tint.

#### PA-69 · Two declared animations never run: the bot-acting pulse and the GameOver confetti

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; not observed at runtime · **Effort:** S

**Location:** `Features/Night/NightWakeUpView.swift:24-26`, `Features/Night/NightWakeUpView.swift:1039-1040`, `Features/GameOver/GameOverView.swift:219-268`

**Problem.** The bot-acting view exists only while `showBotActing` is true, so its scale starts at 1.1. `.animation(value:)` reacts only to the later change, and that change removes the view, so it never pulses. `ConfettiOverlay` animates `t` to `2π`, but `Canvas` does not interpolate that value, and `sin` gives the same result at `2π` as at 0. The confetti is therefore static.

**Evidence.** `NightWakeUpView.swift:893` sets `showBotActing = true` before the view exists, and `:1039` is `.scaleEffect(showBotActing ? 1.1 : 1.0)`. `GameOverView.swift:238` uses `sin(t + CGFloat(i) * 0.5)`, and :264 sets `t = .pi * 2`.

**Impact.** No CPU, GPU or reliability cost; two decorations silently do nothing. The risk is that a naive future fix redraws every frame for as long as GameOver stays open.

**Solution.** For the pulse, use `.phaseAnimator([1.0, 1.1])` or drop the scale. For the confetti, delete it, or drive it with a `TimelineView` that is paused for Reduce Motion and stopped after a few seconds. Fix the misleading comments.

**Risk.** None if the effects are deleted.

#### PA-70 · Accessibility identifiers are built from labels with a regex on every render, and nothing reads them

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `Core/UI/DesignSystem.swift:511-517`, `Core/UI/DesignSystem.swift:543-567`, `Features/Night/NightWakeUpView.swift:1116`, `Features/Voting/VotingView.swift:204`

**Problem.** `accessibleButton` and `accessibleSelection` always set an accessibility identifier built from the label, often a player name, using a regex replacement. Every tap in the night and voting lists re-renders every row, so the regex runs again for each one.

**Evidence.** `DesignSystem.swift:559-563` uses `replacingOccurrences(of: "[^a-z0-9]+", ..., options: .regularExpression)`; there are 14 call sites. There is no UI-test target, and nothing reads the `ui.*` identifiers. Names with no Latin letters or digits all become `"ui."`. The RoleReveal buttons (:170-171, :290-291) also carry a second, explicit `automationID`.

**Impact.** CPU cost is negligible, about 19 short replacements per tap with 19 players. There is no reliability effect today; identifiers would collide or conflict if automation were added.

**Solution.** Remove the identifier from both helpers and delete `accessibilityIdentifierSlug`. Where tests need a stable ID, use the existing `automationID` with fixed keys, such as `solo.night.target.<number>`.

**Risk.** Low.

#### PA-71 · Solo screens create a new haptic generator on every tap without calling `prepare()`

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; latency effect inferred · **Effort:** S

**Location:** `Features/Night/NightWakeUpView.swift:168-169`, `Features/Night/NightWakeUpView.swift:547-548`, `Features/Assignments/RoleRevealView.swift:157-158`, `Features/Multiplayer/Flow/MultiplayerNightView.swift:553`

**Problem.** Each tap creates a new `UINotificationFeedbackGenerator` or `UISelectionFeedbackGenerator` and fires it immediately, without `prepare()`. The same pattern appears at :233-234, :869-870 and `MultiplayerNightView.swift:647-648`.

**Evidence.** `NightWakeUpView.swift:547-548`: `let generator = UISelectionFeedbackGenerator(); generator.selectionChanged()`. Corrections to the original finding: the claimed double haptic (:700-715) cannot happen, because mafia players are not in the mafia target list (:653). The bot-turn haptic intentionally matches the haptic for a human's Continue tap.

**Impact.** Polish only: a possible small delay on the first haptic (inferred). CPU cost is not measurable.

**Solution.** Use `.sensoryFeedback(...)`, as `CreateGameView.swift:76` already does, or keep one generator per view and prepare it ahead of time. Keep the bot and human haptics identical.

**Risk.** None.

#### PA-72 · Sound warm-up runs on the main thread at launch, and the audio session is set up again after every `.inactive`

**Severity:** Low · **Status:** Needs Further Investigation · **Evidence:** Inferred; audio threads at launch measured (PA-55) · **Effort:** S

**Location:** `App/mafia_managerApp.swift:32-35`, `App/mafia_managerApp.swift:38-42`, `Core/Gameplay/Services/SoundManager.swift:24-41`, `Core/Gameplay/Services/SoundManager.swift:47-73`

**Problem.** The root `.onAppear` calls `warmUp()`, which creates four `AVAudioPlayer`s on the main thread before any audio category is set. Every user pays for this, including those who only play multiplayer, which plays no sounds. `handleBackgrounding()` also runs on `.inactive`, so the next `play()` calls `setCategory` and `setActive(true)` again on the main thread. The launch warm-up is the same issue as PA-55; this entry adds the audio-session handling.

**Evidence.** Measured: on the Intro screen the app is already running audio threads, and launch is 0.3–0.4 s slower than a bare SwiftUI app. That total is not broken down by function. `docs/SESSION_CHANGES.md:965` records 84 ms or more per player creation on the main thread.

**Impact.** Estimated: tens of ms up to about 100 ms on a cold launch. The repeated setup after `.inactive` is close to free. Inferred: warming up under the default category may interrupt music the user is playing. To check: add signposts around `warmUp`, and launch with music playing.

**Solution.** Set `.playback` with `.mixWithOthers` before warming up. Move `warmUp()` out of launch as PA-55 describes (the Start Night action, or role reveal). Reset the session flag only on `.background`, and only together with an `AVAudioSession.interruptionNotification` observer, because the `.inactive` reset is today's only recovery after Siri or a call (PA-05). If the `setCategory`/`setActive` calls move off the main thread, use `Task.detached` or a serial queue, because a plain `Task {}` stays on MainActor here; keep building the players on the main actor (PA-55).

**Risk.** Test with the silent switch, background music, a phone call, and auto-lock.

#### PA-73 · `SetupView.body` takes over a second to type-check, and the night wake-up screens repeat one block three times

**Severity:** Low · **Status:** Recommended · **Evidence:** Measured (`-debug-time-function-bodies`) · **Effort:** M

**Location:** `Features/Setup/SetupView.swift:24-457`, `Features/Setup/SetupView.swift:365-399`, `Features/Night/NightWakeUpView.swift:260-486`, `Project.swift:73`

**Problem.** `SetupView.body` is a single 434-line expression, and its Continue button is duplicated (:365-380 and :384-399). NightWakeUpView repeats a block of about 75 lines three times; the copies differ only in role details. The project sets no compile-time warning budgets.

**Evidence.** Measured type-check times for the slowest bodies: `SetupView.body` 1080 ms (3.28 s for the whole file), `LoadCustomRoleConfigSheet.body` 438 ms, `SettingsView.body` 436 ms, `JoinGameView.body` 426 ms. NightWakeUpView is not among the slowest. Incremental Debug builds take 4.0 s after editing one view.

**Impact.** Builds are not a day-to-day bottleneck (measured). The verifier's "tens to hundreds of ms" estimate understated SetupView. The triplicated block is a maintainability problem, not a speed problem.

**Solution.** Split SetupView into `PlayerNameRow`, `BotCounterCard` and `SetupBottomBar` subviews, and merge the three wake-up blocks into one `RoleWakeUpContent`. Add `-warn-long-function-bodies` for Debug only. At a 200 ms threshold, ten bodies would warn today.

**Risk.** Low. Keep the `solo.setup.*` IDs unchanged.

#### PA-74 · Saved solo games can be lost silently on model changes: `load()` swallows decode errors and nothing shows them

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; latent · **Effort:** S

**Location:** `Core/Gameplay/Services/Persistence.swift:66-74`, `Core/Gameplay/Models/NightAction.swift:19-25`, `Core/Gameplay/Store/GameStore.swift:26-36`, `App/mafia_managerApp.swift:36-40`

**Problem.** The solo game models use Swift's automatically generated decoding. That decoding ignores default values, so a field like `var isBot: Bool = false` that is missing from an older save makes decoding fail. `load()` then returns nil and the store starts empty. The next `.inactive` or `.background` overwrites the unreadable file with that empty state. Save errors are copied into `persistenceError`, but no view displays it.

**Evidence.** `Persistence.swift:71-72` is `} catch { return nil }`. `mafia_managerApp.swift:40` is `try? Persistence.shared.saveImmediately(gameStore.state)`. `persistenceError` appears only at `GameStore.swift:11` and :29.

**Impact.** No user is affected today; the most recent model additions are Optional. The next non-Optional field, or a renamed enum case, would silently wipe an in-progress game of 15–30 minutes.

**Solution.** Make new fields Optional or decode them with `decodeIfPresent ?? default`. If a schema version is added, it needs the same treatment. On a decode error, move the file aside before any save, show `persistenceError` to the user, and add a test that decodes a v5.0 save file.

**Risk.** Low.

#### PA-103 · The Game Over screen is the most expensive solo screen: a ~95 ms commit when it appears and a ~37 MB memory spike when it is left

**Severity:** Low · **Status:** Needs Further Investigation · **Evidence:** Measured (Core Animation Commits instrument, `footprint` sampling); cause inferred · **Effort:** S–M

**Location:** `Features/GameOver/GameOverView.swift:9-30` (the whole event log is one `Text(logText)` inside a `cardStyle` card in a `ScrollView`, and `exportLogText` is rebuilt on every body evaluation); `GameOverView.swift:112-113` and `:155-156` (stacked glow shadows); `GameOverView.swift:164-168` (Play Again: `resetAll()` then `dismiss()`, then `GameModeSelectionView` re-pushes `SetupView` through a hidden `NavigationLink(isActive:)`).

**Problem.** In an automated solo game, 271 of 274 Core Animation commits took under one frame (median 0.09 ms, p95 4.1 ms). The exceptions were the first frame at launch (276 ms), one 19 ms commit, and a **95 ms commit when the Game Over screen appeared**. Leaving the screen through **Play again** raises the footprint from 72 MB to 105–109 MB within about 0.4 s, and it drops to 64 MB about 0.6 s later. The 171 MB lifetime peak seen over five games is the same spike after a longer game. Memory before and after is otherwise flat.

**Evidence.**
- Measured on the Release build:
  - Commit durations: Core Animation Commits instrument, suspended-launch attach.
  - Footprint around the tap: about 10 samples per second.
- Reproduced on the Debug build: the peak rose by 29–39 MB on the same tap.
- The allocation source was **not attributed**:
  - The Allocations template recorded, but its data cannot be exported by `xctrace`.
  - `malloc_history -highWaterMark` refused, because the simulator stayed in lite logging mode.
- A plausible cause, not verified: rasterising the full-height shadowed log card for the transition. One full-height bitmap of three pages at 3× is 1206 × 7866 px × 4 B ≈ 38 MB. This is consistent with PA-67.

**Impact.** About 0.1 s of hitching as the result appears, and a short memory spike, once per game. It is not a crash risk at these sizes, but it grows with the length of the event log, so 19-player games make it worse.

**Solution.**
1. Profile on a device with Allocations + VM Tracker and the Hitches instrument to confirm the cause.
2. If it is the card:
   - Render the log as a `LazyVStack` of lines instead of one `Text`.
   - Move the shadow to a fixed-size background shape, or drop it on this card.
   - Compute `logText` once in `onAppear` or in the store.

**Risk.** Low; visual-only changes.

### 4.7 Low severity · Layout and devices

#### PA-75 · Spacers around the multiplayer vote list and night target grid waste height; the predicted stall did not reproduce

**Severity:** Low (auditor: Medium; verified: High; lowered by me because rendering showed no stall) · **Status:** Recommended · **Evidence:** Measured (portrait iPhone 17); small phones, 19 players and accessibility text sizes not measured and need further investigation · **Effort:** S

**Location:** `Features/Multiplayer/Flow/MultiplayerVotingView.swift:58-96`, `Features/Multiplayer/Flow/MultiplayerNightView.swift:82-95`, `Features/Multiplayer/Flow/MultiplayerNightView.swift:500-571`, `Features/Multiplayer/Flow/MultiplayerVotingResultsView.swift:74-94`

**Problem.** The vote list `ScrollView` sits between two flexible `Spacer()`s, and so does the night role section that holds the target grid. Nothing gives the list `.layoutPriority`, so the Spacers keep part of the spare height. The auditor and verifier predicted from layout arithmetic that the list would get about a third of it: about 1.5 vote rows, and 0–8 pt of grid for mafia, which would stall the night.

**Evidence.** `MultiplayerVotingView.swift:58` `Spacer()`, `:77` `ScrollView {`, `:96` `Spacer()`; `MultiplayerNightView.swift:82` and `:95` wrap `roleSpecificView`. Measured on a portrait iPhone 17 (402x874 pt): the non-host vote list is 281 pt tall for 828 pt of content with 12 players (about 3.7 rows), 346 pt for the host. In an 8-player game the non-host mafia grid is 289 pt for 227 pt of content (all 6 targets visible), the mafia host's 226 pt, the doctor's 378 pt. The Spacers leave blank bands of about 60–80 pt above and below. The equal-share arithmetic was wrong.

**Impact.** Polish: more scrolling than needed and an unbalanced screen. No stall on a standard phone at default text size. Unmeasured: iPhone SE height, 19-player games (4 teammate pills, a longer grid) and accessibility sizes. Landscape is PA-15.

**Solution.** Add `.layoutPriority(1)` to the vote `ScrollView`, and wrap the night role content in `Group { … }.layoutPriority(1)`. The Spacers then shrink to their minimum, and role views without a list stay centred. Optionally do the same for the tally lists in `MultiplayerVotingResultsView` and solo `VoteResultsView.swift:43-115`. Then measure on an SE, with 19 players and at an accessibility size.

**Risk.** Low. Keep the existing `.automationID`s, and check that the buttons stay above the home indicator.

#### PA-76 · Lobby footer space comes from a hard-coded spacer, so at accessibility text sizes the footer can cover the last player rows

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; overlap sizes estimated, not rendered · **Effort:** S

**Location:** `Features/Multiplayer/Flow/MultiplayerLobbyView.swift:205-207`, `Features/Multiplayer/Flow/MultiplayerLobbyView.swift:211-278`, `Features/Multiplayer/Flow/MultiplayerLobbyView.swift:283-295`

**Problem.** `lobbyContent` overlays an opaque footer (Start Game, validation or error text, Leave) on the `ScrollView` in a `ZStack`. The scroll content reserves room for it with a `Color.clear` whose height is built from constants, not from the footer's real height. All fonts scale with Dynamic Type, and nothing caps the scaling.

**Evidence.** `:205` `Color.clear.frame(height: calculateButtonHeight())`, `:288` `height += 120 // Button + validation messages`, `:292` `height += 56`. With stack spacing and `.padding(.bottom, 20)` the real clearance is 240 pt (host) and 120 pt (guest). The verifier's estimates: at default size the host footer is about 160 pt, or about 208 pt with a 2-line start error, so nothing overlaps up to xxxLarge. With a start error the overlap is about 40 pt at AX1 and about 140 pt (roughly two player rows) at AX3.

**Impact.** Only users with accessibility text sizes, and only after a start error or with fewer than 4 players. The host cannot scroll the hidden rows or their remove buttons into view. No CPU or network cost.

**Solution.** Delete `calculateButtonHeight()` and the spacer. Use the `ScrollView` alone and move the footer into `.safeAreaInset(edge: .bottom, spacing: 0) { … }`, as 8 other screens already do (for example `MorningSummaryView.swift:59`).

**Risk.** Very low. The outer background is also `surface0`, and the `multiplayer.lobby.startGame` / `.leave` IDs are unaffected.

#### PA-77 · In iPhone landscape with the keyboard up, SetupView's footer hides the name field and the guest "Start Playing" button sits under the keyboard

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified layout; keyboard and bar heights estimated, not rendered · **Effort:** S

**Location:** `Features/Setup/SetupView.swift:321-424`, `Features/Auth/GuestNameInputView.swift:18-122`, `Features/Setup/SetupView.swift:282-283`, `Project.swift:35-39`

**Problem.** iPhone landscape is enabled. SetupView's `.safeAreaInset(edge: .bottom)` footer (a grid row plus the CTA, about 166 pt at default size) rides on top of the keyboard. That leaves roughly 0–35 pt of list below the 32 pt nav bar, so the focused name field (about 50 pt) cannot be fully seen. `GuestNameInputView` focuses its field on appear and has no `ScrollView`. Its stack of about 334 pt is centred in the 150–190 pt above the keyboard, so the button ends up under it.

**Evidence.** `GuestNameInputView.swift:121` `isNameFieldFocused = true`. `:58` `.onSubmit` still submits from the Done key, so the screen is degraded, not blocked. Guests count as `isAuthenticated` (`AuthStore.swift:323-327`), so the two-row footer applies to every user with a session.

**Impact.** A usability annoyance on one screen at game start, with no data loss or crash. iPad mini in landscape keeps about 100 pt of list. Portrait is unaffected. A portrait lock (PA-15) removes the iPhone cases.

**Solution.** SetupView: track `@FocusState` on the rows and hide the Load Group / Load Roles row while editing, or move both into a toolbar `Menu`. Add `.scrollDismissesKeyboard(.interactively)`. GuestNameInputView: put the title and field in a `ScrollView` and pin the button with `.safeAreaInset(edge: .bottom)`. The 220/120 pt `Color.clear` spacer (:282-283) is redundant but was added on purpose (7033af3). Remove it in a separate change and check the result visually.

**Risk.** Very low. Check that the load sheets still open after the keyboard is dismissed.

#### PA-78 · Mafia role reveal puts all teammate pills in one non-wrapping HStack, so long names break mid-word in large games

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; name widths measured from the SF Rounded font file, layout not rendered · **Effort:** S

**Location:** `Features/Multiplayer/Flow/MultiplayerRoleRevealView.swift:73-98`, `Features/Multiplayer/Flow/MultiplayerRoleRevealView.swift:110-131`, `Core/Multiplayer/Store/MultiplayerGameStore.swift:80-83`

**Problem.** Every mafia teammate is a pill in `HStack(spacing: 10)` (:80), with no `lineLimit`, wrapping or scrolling, on a screen that cannot scroll. Games of 15–19 players have 5 mafia, so 4 teammates.

**Evidence.** Each pill has about 47 pt of fixed width, which leaves about 175 pt for four names on a 393 pt phone (157 pt on a 375 pt SE). At 17 pt, "Alexander" is about 72 pt and "Christopher" about 84 pt. Four names of 6+ letters therefore squeeze to about 44 pt each and break onto 2 lines. Bot names (`Bot N`, 35–45 pt) mostly fit. The night view already wraps the same pills in `ScrollView(.horizontal)` (`MultiplayerNightView.swift:311-329`).

**Impact.** Cosmetic: teammate names break mid-word on the mafia's private briefing in 15–19 player games, and in 9–14 player games on 375 pt phones with long names. The auditor's claim that the confirm button gets clipped is unlikely at default text size. That only happens at accessibility sizes or in landscape, and then for every role (PA-15).

**Solution.** Use a layout that wraps and keeps every name visible, for example `ViewThatFits(in: .horizontal) { HStack { pills }; LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))]) { pills } }`, with `.lineLimit(1)` on each name. A horizontal `ScrollView` also works, but it hides teammates off-screen and needs `.defaultScrollAnchor(.center)` to stay centred.

**Risk.** Very low; only this view changes.

#### PA-79 · iPad runs stretched phone layouts with no size-class or readable-width handling

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; iPad mini landscape overflow inferred · **Effort:** M

**Location:** `Project.swift:22`, `Features/Multiplayer/Flow/MultiplayerNightView.swift:533-539`, `Features/Multiplayer/Flow/MultiplayerVoteDeathRevealView.swift:51-73`, `Core/UI/DesignSystem.swift:193-194`

**Problem.** The app ships to iPad (`destinations: [.iPhone, .iPad]`) with all four orientations, so Split View and Stage Manager are available. No view adapts: there is no `horizontalSizeClass`, `ViewThatFits`, readable-width cap or `NavigationSplitView`. The only numeric `maxWidth` is `ProfileView.swift:35`.

**Evidence.** CTAs use `.frame(maxWidth: .infinity)` (`DesignSystem.swift:194`), so they are about 1340 pt wide on a 13-inch iPad in landscape. The night grid has three `GridItem(.flexible())` columns (:535-537), about 440 pt per cell around a 48 pt icon. The reveal card is `.frame(width: 280, height: 380)` (:61). It does not clip at 320 pt width (the auditor overstated this); the real risk is height. The verifier estimates an eliminated host's reveal screen at about 776 pt, against about 650 pt usable on a full-screen iPad mini in landscape.

**Impact.** Mostly cosmetic on full-screen iPad. In short windows, and probably on iPad mini in landscape, the Continue button can be pushed off-screen (same mechanism as PA-15). iPad has never been tested (`docs/SESSION_CHANGES.md:265`).

**Solution.** Add a `readableWidth` modifier (`frame(maxWidth: 640).frame(maxWidth: .infinity)`). Apply it to each screen's content stack, not to the `ZStack`, so the backgrounds still fill the window. Give each grid its own adaptive minimum: `.adaptive(minimum: 100, maximum: 180)` for the night grid, and about 150 for `VotingView` so the iPhone keeps two columns. Make the reveal screen scroll. If iPad is not a goal, drop `.iPad` from `destinations` instead.

**Risk.** Low. Width caps only change the iPad look. Removing `.iPad` is a product decision.

### 4.8 Low severity · Build, dependencies and tooling

#### PA-80 · Release-simulator builds also compile every dependency for x86_64

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Measured (verifier, from a clean Release-simulator build log) · **Effort:** S

**Location:** `Tuist/Package.swift:7-14`, `Project.swift:9-10`

**Problem.** `EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64` is set only in the app project's base settings. Tuist generates separate projects for the packages, and `PackageSettings` sets nothing for them. When `ONLY_ACTIVE_ARCH=NO`, as in Release and the Release-simulator validation builds, every dependency is built for both x86_64 and arm64. The x86_64 slices are never linked.

**Evidence.** Measured by the verifier: Nuke, NukeUI, PhoneNumberKit, ClerkKit, ClerkKitUI, UniFFI and ConvexMobile compiled for both architectures; the app compiled for arm64 only. The x86_64 work was about 129 CPU-s, about 48% of roughly 271 CPU-s, and ClerkKitUI alone was 56.5 CPU-s. It added only about 2 s to the 123.5 s wall time.

**Impact.** Wasted CPU and energy on clean Release-simulator builds, which every fresh agent worktree repeats. The auditor's "minutes" of wall time is wrong. Debug, test and device builds are unaffected.

**Solution.** Pass `baseSettings: .settings(base: ["EXCLUDED_ARCHS[sdk=iphonesimulator*]": "x86_64"])` to `PackageSettings`; the Tuist 4.198.1 initializer accepts it. Then run `tuist install && tuist generate`. Passing `EXCLUDED_ARCHS=x86_64` to xcodebuild also works. `ONLY_ACTIVE_ARCH=YES` does not help with `generic/platform=iOS Simulator`. Removing ClerkKitUI (PA-18) removes the largest share.

**Risk.** Low. The app already refuses x86_64 simulators.

#### PA-81 · App builds in Swift 5 mode with minimal concurrency checking

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Code-verified; Swift 5 mode confirmed in my Release build settings; Swift 6 crash risk inferred · **Effort:** M

**Location:** `Project.swift:5-18`, `Core/Backend/ConvexService.swift:122-139`, `Core/Backend/ConvexService.swift:27-39`

**Problem.** `Project.swift` sets `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` but neither `SWIFT_VERSION` nor `SWIFT_STRICT_CONCURRENCY`. The app therefore compiles in Tuist's default Swift 5 mode with minimal concurrency diagnostics.

**Evidence.** My Release build used `SWIFT_VERSION 5` with MainActor default isolation. The verifier found almost all code on the main actor: no `Task.detached`, no actors, and subscriptions hop back with `.receive(on: DispatchQueue.main)`. The races in `SESSION_CHANGES` are ordering races, which strict checking would not catch. The one off-main path is the `Publisher.async()` bridge used by `query`, whose MainActor-inferred `sink` closures run on Convex FFI threads. The clean build already warns at `ConvexService.swift:48` about an isolated `Decodable` conformance (measured, PA-91).

**Impact.** No runtime cost and no demonstrated defect. Stricter checking would mainly protect future nonisolated code. Switching to Swift 6 without preparation would likely trip the runtime isolation check in that bridge on every `ConvexService.query` (inferred).

**Solution.** Do it in stages. First add `SWIFT_STRICT_CONCURRENCY = complete`, which only warns in Swift 5 mode, and fix the warnings. Make `Publisher.async()` `nonisolated`, or add `.receive(on: DispatchQueue.main)` before `.first()`. Then set `SWIFT_VERSION = 6.0` in Debug and run the multiplayer flows with the Main Thread Checker on.

**Risk.** Medium for the Swift 6 switch (runtime isolation failures), low for the warnings-only step. Given the Low severity, do it when convenient.

#### PA-82 · Pre-Tuist helper scripts are stale but still advertised as the simulator workflow

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; Keychain effect of ad-hoc signing inferred · **Effort:** S

**Location:** `scripts/run_ios_sim.sh:12-43`, `scripts/add_files_to_xcode.rb:5-65`, `buildServer.json:15-16`, `AGENTS.md:65`

**Problem.** `AGENTS.md` and `docs/CLAUDE_PRIMER.md` present `run_ios_sim.sh` as the simulator helper, but it predates Tuist. It builds `-project mafia_manager.xcodeproj` without running `tuist install` or `tuist generate`, even though that project is gitignored and currently has no `project.pbxproj`. It also disables signing and re-signs ad hoc without entitlements. `add_files_to_xcode.rb` writes file references into the generated pbxproj through a hard-coded absolute path. `AGENTS.md` forbids that, and the Project.swift globs make it pointless. The tracked `buildServer.json` points at a DerivedData folder and workspace that no longer exist.

**Evidence.** `run_ios_sim.sh:20` `-project "$PROJECT_PATH"`, `:25` `CODE_SIGNING_ALLOWED=NO`, `:40` `codesign --force --sign -`; `add_files_to_xcode.rb:59` `target.add_file_references`. The auditor's claim that `cc_env.sh` uses a missing `stdbuf` is wrong (`/usr/bin/stdbuf` exists). That script is simply unused.

**Impact.** Costs developer and agent time only. On a fresh clone the helper fails or builds a stale project. A successful build loses the associated-domains entitlement, and guest auth depends on the Keychain (effect inferred). No app runtime impact.

**Solution.** Delete `add_files_to_xcode.rb`. Rewrite `run_ios_sim.sh` to run `tuist install && tuist generate --no-open`, build `-workspace mafia_manager.xcworkspace` with normal local signing (or wrap `tuist run`), and print the log path on failure. Update `AGENTS.md:62-66` and `docs/CLAUDE_PRIMER.md:13-15` to match. Untrack `buildServer.json` and regenerate it locally with `xcode-build-server config`.

**Risk.** None for the app.

#### PA-83 · Tuist, Xcode and Node versions and the Release build settings are not pinned

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; current Release settings measured · **Effort:** S

**Location:** `Tuist.swift:3-5`, `Project.swift:5-17`, `Project.swift:66-76`, `package.json:5-7`

**Problem.** Nothing pins Tuist. It is installed as a Homebrew cask, and the repo has no `mise.toml`, `.tool-versions` or `.tuist-version`. `Tuist.swift` accepts any Xcode, and there is no `.nvmrc` (`engines` only warns). Release optimization, compilation mode, dead stripping, dSYM format and `SWIFT_VERSION` all come from Tuist defaults.

**Evidence.** `Tuist.swift:4` `compatibleXcodeVersions: .all`. My Release build used `-O`, whole-module compilation, dead-code stripping and `SWIFT_VERSION 5`, so today's defaults are fine. The Homebrew receipt shows this machine has already moved from Tuist 4.134.0 to 4.198.1 without the repo noticing. SwiftPM (`Tuist/Package.resolved`) and the Convex CLI (`package-lock.json`, 1.46.0) are already pinned.

**Impact.** No runtime cost. A Tuist or Xcode upgrade could change Release codegen or the Swift language mode, or break `tuist generate`, so two machines could produce different binaries. Unlikely, but hard to diagnose.

**Solution.** Add a `mise.toml` with `tuist = "4.198.1"` and `node = "22.12"`. Set `compatibleXcodeVersions: .upToNextMajor("27.0")`; the auditor's `"26.0"` would block the Xcode 27 toolchain in use. Declare the Release keys and `SWIFT_VERSION = 5` explicitly in Project.swift or the xcconfigs. Pinning the `@latest` MCP servers in `.mcp.json` is agent-tooling hygiene only (PA-87).

**Risk.** Very low.

#### PA-84 · SwiftPM `from:` ranges let clerk-ios drift across breaking 1.x releases on the next dependency update

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; upstream releases checked by the verifier · **Effort:** S

**Location:** `Tuist/Package.swift:20-21`, `Tuist/Package.resolved:9,18`, `Vendor/clerk-convex-swift/Sources/ClerkKitConvex/ClerkConvexAuthProvider.swift:141-199`

**Problem.** `from: "0.8.0"` and `from: "1.0.0"` accept anything below the next major version. The committed `Package.resolved` pins clerk-ios 1.1.1 and convex-swift 0.8.1, so normal installs are safe. But `tuist install --update` or a full re-resolve moves to the newest allowed release. The vendored bridge and `AuthService` use about ten Clerk auth APIs, such as `session.getToken(.init(template:))`, `Clerk.shared.auth.events` and `.signUpCompleted`.

**Evidence.** The verifier checked upstream. clerk-ios is at 1.6.1, and its 1.5.8 and 1.6.1 releases include changes marked breaking (`!`), one of them in a patch release. 1.5.8 also changed refreshed-token syncing, which the bridge depends on. convex-swift has nothing newer than 0.8.1, so that half is only a future risk. The `IgnoredResult` mutation workaround (`ConvexService.swift:55-67`) would survive an upstream fix.

**Impact.** None at runtime today. A blanket update would jump clerk-ios five minor versions and could break the build or quietly change sign-up and token refresh. Without CI (PA-19), only manual testing would catch that.

**Solution.** Pin clerk-ios with `exact: "1.1.1"`; `.upToNextMinor` would not stop a breaking patch release. Use `.upToNextMinor(from: "0.8.1")` or `exact` for convex-swift. Bump deliberately, re-test the bridge and the AuthService flows, and record each bump in `docs/SESSION_CHANGES.md`. Removing the unused ClerkKitUI (PA-18) shrinks the surface.

**Risk.** Very low. Nothing else in the graph depends on either package, so exact pins cannot cause resolution conflicts.

#### PA-85 · Asset catalogs reference a missing AccentColor, carry an unused icon PNG, and include a stray second catalog

**Severity:** Low · **Status:** Recommended · **Evidence:** Measured (warnings in my clean build, PA-91) · **Effort:** S

**Location:** `Project.swift:69`, `Assets.xcassets/AppIcon.appiconset/Contents.json:4`, `mafia_manager/Assets.xcassets/AppIcon.appiconset/Contents.json:4`

**Problem.** `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` is `AccentColor`, but no `AccentColor.colorset` exists. `AppIcon.appiconset` holds a `Logo-1024-temp.png` (148,743 bytes) that `Contents.json` never references. A second catalog, `mafia_manager/Assets.xcassets`, is in neither sources nor resources and points at an `AppIcon-1024.png` that does not exist.

**Evidence.** Measured: the clean Debug build warns "Accent color 'AccentColor' is not present in any asset catalogs" and that AppIcon "has an unassigned child" (the temp PNG). The verifier found no `NSAccentColorName` in the generated Info.plist and no temp PNG in `Assets.car`.

**Impact.** Two warnings on every build and about 149 KB of dead binary in git. Nothing extra ships. Users see no accent difference: the app's tint `#0A84FF` equals `systemBlue` in dark mode, the app forces dark mode, and it never uses `ASWebAuthenticationSession`.

**Solution.** Delete `Project.swift:69`, or add an `AccentColor.colorset` set to `#0A84FF`. `git rm` the temp PNG and the `mafia_manager/` directory, then run `tuist generate`. Adding dark and tinted icons is optional.

**Risk.** None.

#### PA-86 · Blank launch screen follows the system appearance, so light-mode users see a white frame before the dark UI

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; the white frame follows from documented `UILaunchScreen` behaviour, not recorded · **Effort:** S

**Location:** `Project.swift:34`, `App/mafia_managerApp.swift:31`, `Core/UI/DesignSystem.swift:7`

**Problem.** `"UILaunchScreen": [:]` has no `UIColorName`, so iOS paints `systemBackground`, which is white in light mode. The app forces dark mode only in SwiftUI, with `.preferredColorScheme(.dark)` over `surface0` (`#0A0C10`), and that applies only from the first rendered frame.

**Evidence.** `Project.swift:34` `"UILaunchScreen": [:],`. `mafia_managerApp.swift:31` is the only runtime `.preferredColorScheme(.dark)`. The repo has no `UIUserInterfaceStyle` key, launch storyboard or colour asset.

**Impact.** Cosmetic. Light-mode users see a white flash on every cold launch; warm resumes show a snapshot instead. Dark-mode users see an almost invisible step from black to `#0A0C10`. The claim that launch "feels slower" is a perception, not a measurement.

**Solution.** Add a `LaunchBackground.colorset` set to `#0A0C10`, set `"UILaunchScreen": ["UIColorName": "LaunchBackground"]` in Project.swift, and run `tuist generate`. You can also add `"UIUserInterfaceStyle": "Dark"`, but on its own that gives `#000000`, not an exact match. Keep `.preferredColorScheme(.dark)`.

**Risk.** Very low. iOS caches launch screens, so checking the change may need an app reinstall.

#### PA-87 · Tracked agent configs default to bypassPermissions, keep a dead Supabase entry with a public anon key, and run unpinned MCP servers

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `.claude/settings.json:3`, `.gemini/settings.json:9-13`, `.mcp.json:3-6`, `.mcp.json:12`

**Problem.** Three agent configs are committed. `.claude/settings.json` sets `"defaultMode": "bypassPermissions"` for everyone who clones the repo. `.gemini/settings.json` contains an `Authorization: Bearer <redacted>` header for the legacy Supabase project. `.mcp.json` still wires the decommissioned Supabase MCP and runs `convex@latest` and `xcodebuildmcp@latest`, and `.gemini/settings.json:7` runs `ios-simulator-mcp` with no version.

**Evidence.** The verifier decoded only the token's claims. It is a Supabase anon-role key: a public client credential that already shipped in the legacy app, and whose project ref is already in git history. The Convex MCP cannot reach prod unless started with `--dangerously-enable-production-deployments`, which `.mcp.json` does not pass. Under bypass mode, though, a Bash `npx convex deploy` still runs without a prompt.

**Impact.** No app runtime impact. The tracked bypass default only affects other people who clone the repo; the only human developer already sets it at user and local level. The anon key adds negligible exposure. Unpinned MCP packages are a small supply-chain and reproducibility risk for tooling.

**Solution.** Move `defaultMode` to the gitignored `settings.local.json` and keep the deny rules. Optionally add ask or deny rules for `npx convex deploy*` and `npx convex run --prod*`. Remove the dead Supabase entries now. Do not rotate the anon key until the legacy app is retired, because `docs/SESSION_CHANGES.md:711-717` keeps that project active. Pin `convex@1.46.0` and the other MCP packages.

**Risk.** None for the app. Rewriting git history is not warranted.

#### PA-88 · Backend tests in `tests/convex/` are never type-checked

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `convex/tsconfig.json:23-24`, `vitest.config.ts:3-8`, `package.json:11`, `tests/convex/helpers.ts:1-6`

**Problem.** The only TypeScript project is `convex/tsconfig.json`. Its include paths resolve relative to `convex/`, and no Convex file imports from `tests/`. Vitest strips types without checking them, and no typecheck option is set. The 8 test files (75,678 bytes) are therefore never type-checked. The "tsc clean" and "typecheck passed" notes in SESSION_CHANGES cover `convex/` only.

**Evidence.** `convex/tsconfig.json:23-24` `"include": ["./**/*"], "exclude": ["./_generated"]`; `package.json:11` `"test:backend": "vitest run"`. No root or `tests/` tsconfig exists or has ever existed in git history.

**Impact.** Developer loop only. Runtime checks already catch most contract drift: convex-test runs argument validators (inferred), and several tests pin exact result keys (`identity.test.ts:14`, `privacy.test.ts:32`). What slips through is type-only mistakes, for example `any`-typed helpers (`play.test.ts:12`). The auditor's claim that this bit during the contract-4 refactor is unsupported; the tests changed in the same commits.

**Solution.** Add `tests/tsconfig.json` extending `../convex/tsconfig.json` with `"include": ["./**/*.ts"]`, and chain it: `"test:backend": "tsc -p tests --noEmit && vitest run"`. PA-19's CI job would run the same command. Vitest's `typecheck.enabled` alone is not enough: by default it checks only `*.test-d.ts` files, and its support for the pinned TypeScript ^7 is unconfirmed.

**Risk.** Low. Expect a few existing errors (`any` under strict mode, non-null assertions) to fix first.

#### PA-89 · Repo clutter: stale in-repo DerivedData, a restored vendored xcodeproj, root build logs, design binaries, diverged skill copies

**Severity:** Low · **Status:** Recommended · **Evidence:** Measured (sizes) and code-verified · **Effort:** S

**Location:** `Vendor/clerk-convex-swift/ClerkConvex.xcodeproj/project.pbxproj`, `docs/SESSION_CHANGES.md:17`, `.gitignore:2,10,15,23`, `.claude/skills/ios-simulator-skill/SKILL.md`

**Problem.** Stale or unneeded files have built up:
- `DerivedData/` (437 MB, measured) is unused; builds use `~/Library/Developer/Xcode/DerivedData` (`buildServer.json:16`).
- `ClerkConvex.xcodeproj` is back, byte-identical to the file commit 9bf8eb2 deleted, although SESSION_CHANGES.md:17 says it was removed. iCloud most likely restored it (inferred; PA-17).
- `build.log` and two xcodemake logs (839,864 and 848,577 B) sit in the root.
- Tracked, unreferenced `design.png` (436,486 B) and `Mafia_App Screens.pdf` (1,131,823 B).
- Empty directories (`docs 2/`, two `ios-simulator-skill 2/`, `supabase/migrations/`, `.cursor/`), plus two diverged ios-simulator-skill copies.

**Evidence.** Verifier correction: DerivedData, the logs and Vendor `.build`/`Derived` are already gitignored, so `git status` shows only the xcodeproj, as one line among the 45 duplicates. The `.claude` skill copy has two extra files and a different `SKILL.md`.

**Impact.** No runtime, build or user impact. About 439 MB of dead data in an iCloud-synced folder, about 1.5 MB of binaries in HEAD and history (pack 8.43 MiB), and a skills maintenance risk.

**Solution.** Delete the untracked items and empty directories (PA-17's cleanup covers the first three). Archive the design files elsewhere and delete them from HEAD; moving them inside the repo saves nothing, and a history rewrite is not worth it at this size. Merge the skill copies, then symlink one, as is done for the other skills.

**Risk.** None for ignored or untracked files. Merge the skill copies first, or content is lost.

#### PA-90 · Privacy manifest declares no collected data types, though the backend stores email, name, user ID and gameplay data

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `PrivacyInfo.xcprivacy:9-10`, `convex/schema.ts:26-43`, `convex/users.ts:25-33`, `Core/Auth/Services/AuthService.swift:187`

**Problem.** The bundled manifest (`Project.swift:56`) has an empty `NSPrivacyCollectedDataTypes`, but the app's own backend stores data linked to the user. That is email, display name and auth subject in `users`, plus stats, custom role configs and player groups keyed by `user_id`.

**Evidence.** `PrivacyInfo.xcprivacy:9-10` `<key>NSPrivacyCollectedDataTypes</key>` / `<array/>`. `users.ts:25` lowercases and stores `identity.email`, and `:63-73` inserts the row. `AuthService.swift:187` calls `users:ensureUser` for every signed-in account. Names typed for other players are stored too (`player_stats.player_name`, `player_groups.player_names`).

**Impact.** No runtime or performance effect; this is compliance, outside the audit's main lens. Xcode's privacy report understates collection, and an App Store label filled from it would be wrong. Rejection is unlikely: Apple does not check this key against the label (verifier correction).

**Solution.** Declare `EmailAddress`, `UserID`, `Name` and `GameplayContent`, each with Linked=true, Tracking=false and purpose `AppFunctionality`. Optionally add `OtherUserContent` for names typed for other players. Update the App Store Connect privacy answers first; they are the authoritative label.

**Risk.** None at runtime.

#### PA-91 · Clean Debug build emits 27 warnings, including an isolated-conformance warning on the mutation path

**Severity:** Low · **Status:** Recommended · **Evidence:** Measured (clean Debug build) · **Effort:** S

**Location:** `Core/Backend/ConvexService.swift:48`, `App/mafia_managerApp.swift:36`, `Features/Night/NightWakeUpView.swift:537`, `Features/Multiplayer/Flow/MultiplayerLobbyView.swift:65`

**Problem.** A clean Debug build produces 27 warnings. With that much noise, a new warning is easy to miss.

**Evidence.** Measured:
- `ConvexService.swift:48`: "conformance of 'T' to protocol 'Decodable' may be isolated and cannot be passed to @concurrent context [#IsolatedConformances]".
- Deprecated `NavigationLink(destination:isActive:)` at `NightPhaseView.swift:68`, `NightOutcomeView.swift:72`, `GameModeSelectionView.swift:118` and `:124`, and `AssignmentsView.swift:46`, plus five more.
- Deprecated `onChange(of:perform:)` at `mafia_managerApp.swift:36` and `SetupView.swift:297`.
- "ViewBuilder disabled by explicit return" (`NightWakeUpView.swift:537`) and "default will never be executed" (`MultiplayerLobbyView.swift:65`).
- Asset catalog: an unassigned AppIcon child (`Logo-1024-temp.png`) and a missing `AccentColor`.

The remaining warnings were not itemized.

**Impact.** No measured runtime cost. The isolated-conformance warning marks a concurrency gap on the path every mutation takes, which the Swift 6 move (PA-81) will have to resolve anyway.

**Solution.** Deleting the legacy views (PA-60) removes three of the NavigationLink sites, PA-62 replaces the mode-selection links, and PA-85 fixes the catalog. Switch both `onChange` calls to the two-parameter form, and drop the explicit `return` and the unreachable `default`. For `:48`, likely constrain `T` with `SendableMetatype` (SE-0470) or mark the decoded models' conformances `nonisolated`, then confirm the warning clears.

**Risk.** Low. Keep `initial: false` on the `scenePhase` `onChange` so `.appDidBecomeActive` posts exactly as before.

#### PA-102 · After the latest pull, `tuist generate` fails until the stale `Tuist/.build` dependency cache is rebuilt

**Severity:** Low · **Status:** Recommended · **Evidence:** Measured (scratch copy) · **Effort:** S

**Location:** `Tuist/.build/workspace-state.json` (local, git-ignored; last written 2026-05-15). `Vendor/clerk-convex-swift/` no longer has a `Package.swift` at `HEAD`.

**Problem.** The vendored `clerk-convex-swift` used to be a local Swift package. `Tuist/Package.swift` stopped referencing it in `3d0afa4` (2026-07-10), and `9bf8eb2` (2026-10-10) deleted its `Package.swift`. Its sources are now compiled directly into the app through the `Project.swift` glob. The local SwiftPM state in `Tuist/.build` still lists the package. The `git pull` at 00:42 on 2026-10-11 also deleted the 11 previously tracked `.xcodeproj` and `.xcworkspace` files, so a fresh `tuist generate` is now required.

**Evidence.** Both measured on a copy of the cleaned checkout:
- `tuist generate` fails with "Package.swift not found at path …/Vendor/clerk-convex-swift".
- `tuist install` alone does not clear it.
- After `rm -rf Tuist/.build && tuist install && tuist generate`, generation succeeds and the Debug build passes with 0 errors.

**Impact.** Nobody can open or build the project from this checkout until they rebuild the cache, and the error message does not point at the cause. It is local only, with no user or production impact.

**Solution.** Run `rm -rf Tuist/.build && tuist install && tuist generate` once. Optionally note it in `AGENTS.md` next to the existing Tuist commands, since any older checkout that pulls across `9bf8eb2` will hit it.

**Risk.** None. The cache is re-downloaded.

### 4.9 Low severity · Tests

#### PA-92 · Unit tests run inside the full app, which boots Clerk and Convex and shares the real solo save file

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Measured (run timings) and code-verified · **Effort:** M

**Location:** `Project.swift:79-90`, `App/mafia_managerApp.swift:15-16`, `Core/Gameplay/Store/GameStore.swift:21-37`, `Core/Gameplay/Services/Persistence.swift:80-82`

**Problem.** The `.unitTests` target depends on the app, so the app hosts it, and the app has no test-host guard. Launch builds `AuthStore()` → `ConvexService.shared` (`Clerk.configure` plus a WebSocket to the dev deployment), restores the session in a background Task and warms up audio. `GameStoreTests` and `SoloVoteValidationTests` load, overwrite and delete the simulator's real `GameState.json` through `Persistence.shared`. `AuthRegressionTests` stores register on `NotificationCenter.default`.

**Evidence.** Measured: 105 tests (101 passed, 4 skipped) execute in 0.43 s, but the whole `xcodebuild test` run takes about 100–108 s. Most of that is build and install; the host-launch share was not isolated. Code: no `XCTestConfigurationFilePath` guard in `App/`, `Core/` or `Features/`. `reset()` does not cancel the pending 300 ms save, so a test's `defer { resetAll() }` can be undone by a late write (inferred; PA-65).

**Impact.** Developers only; results are correct today. Each run pays one hosted cold launch, which the network does not gate (verifier correction). A run with a stored identity sends dev-deployment mutations and wipes or replaces the simulator's saved solo game.

**Solution.** Guard the host with an `@main enum AppLauncher` that runs a bare test app when `XCTestConfigurationFilePath` is set. Returning `Color.clear` from the current body is not enough, because the `@StateObject` initializers still run. Make `reset()` cancel `saveTask`, and inject `Persistence(directory:)` (default `.shared`). Make `databaseService` lazy, and pass a private `NotificationCenter` in `AuthRegressionTests.makeStore`. Keep a hosted target for the live suites.

**Risk.** Key the guard only on the XCTest variable, never on a build flag that could ship. Keep the `.shared` defaults.

#### PA-93 · Multiplayer host and connection paths have no unit tests and no seam for a fake `SessionService` or the 5 s ticker

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** M

**Location:** `Core/Multiplayer/Store/MultiplayerGameStore.swift:42-50`, `Core/Multiplayer/Store/MultiplayerGameStore+Connection.swift:90-98`, `Core/Multiplayer/Store/MultiplayerGameStore+HostPhases.swift:38-45`, `Core/Multiplayer/Store/MultiplayerGameStore+HostPhases.swift:77-91`

**Problem.** `init` builds a concrete `SessionService()`, which holds `ConvexService.shared`, and binds BotDirector's submissions to it. The ticker sleeps a fixed `Task.sleep(for: .seconds(5))`. As a result, `completeNightPhase`, the role-reveal advance, `claimHost`, heartbeats and bot submissions cannot run against a fake.

**Evidence.** `MultiplayerStoreTests` covers only derived values, `apply()`, `currentRoundId`, `makeAssignments` and `nextHost`. These paths appear only in the opt-in live suite (3 tests), and there is no CI. Correction: some are testable today without a refactor. `updateConnectionStatus` works through the internal `subscriptions` array, and `checkHost`'s branches work with the `Date()`-relative fixtures. The identity-change resubscribe works through a fake-backed `AuthStore`, and so does a background during resume (`tickTask == nil`).

**Impact.** A coverage gap, not a present defect. A dedup-guard regression only costs extra mutations, because `advancePhase`, `recordNightActions` and `resolveNightAtomic` are idempotent on the server. A regression in ticker restart or `claimHost` could stall a 4–19 player room, and nothing would catch it before a manual two-device test.

**Solution.** Write the refactor-free tests first. Then add `init(service: SessionServicing = SessionService(), sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) })`, where `SessionServicing` is a @MainActor protocol over the 17 existing methods. Move `ManualClock` into the shared fixtures. Then test that concurrent `completeNightPhase` calls record and resolve exactly once each, in order, and that a stale host leads to one `claimHost`.

**Risk.** Low if the defaults stay; the app and the live tests call `MultiplayerGameStore()` with no arguments.

#### PA-94 · Live tests switch a process-global guest proof, so retried subscriptions and background requests act as the wrong player

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Code-verified; retry frequency inferred · **Effort:** S

**Location:** `mafia_managerTests/ConvexIntegrationTests.swift:14-15`, `mafia_managerTests/ConvexIntegrationTests.swift:105-123`, `mafia_managerTests/ConvexIntegrationTests.swift:144-146`, `Core/Backend/ConvexService.swift:80-87`

**Problem.** The suite simulates several devices in one process. `act(as:)` sets the global `guestProofProvider`. The header says "Subscriptions keep the proof they started with", but `prepare(args)` reads the current global proof on every call, and the store's arguments carry only `session_id`. Each supervisor reconnect (first-value timeout or failure) therefore subscribes as whichever guest `act(as:)` set last. The server's views derive the viewer from that proof.

**Evidence.** `ConvexService.swift:82-84` adds `guestProofProvider?()` when the arguments lack `guest_secret_hash`, and `SubscriptionSupervisor.swift:91` re-opens the subscription. The identity switches happen at `:105-107` and `:115-119`. Heartbeats are deterministic: from `:107` and `:119` on, the `member` and `relaunched` stores heartbeat as the host. No assertion depends on that today.

**Impact.** Opt-in live suite only; production is unaffected. A retry produces a misleading failure (wrong `myPlayer`, `isHost` or role), or a pass that checks the wrong seat at `:108-109`. How often this happens is not measured; see PA-97 for the likely trigger.

**Solution.** Without app changes, keep one live store per identity at a time, and stop the other stores before switching. Check other identities with one-shot queries that pass `guest_secret_hash` explicitly; `prepare` keeps explicit values. Fix the header comment. If each store must own its identity, inject a proof closure that defaults to the global provider, and send it on every request.

**Risk.** Low. Production relies on re-reading the global proof after identity changes, so keep that as the default.

#### PA-95 · The solo "inspector cannot identify another inspector" test asserts nothing, because 8 players have one inspector

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `mafia_managerTests/GameStoreTests.swift:198-209`, `Core/Gameplay/Store/GameStore.swift:497-500`, `Features/Night/NightWakeUpView.swift:654-655`, `Core/Gameplay/Services/BotDecisionService.swift:45-47`

**Problem.** The test calls `setupGame(playerCount: 8) // Has 2 inspectors` and wraps its only assertions in `if inspectors.count >= 2`. `roleDistribution` gives 6–8 players one inspector and adds a second only from 9 players. The branch never runs, and the test always passes. `docs/AUDIT_2026-03-20.md:285` counted it as verification of MM-08.

**Evidence.** `GameStore.swift:497-498` `case 6...8: return (mafia: 2, doctors: 1, inspectors: 1)`. The same file asserts `inspectorCount == 1` for 8 players at `:63-70`.

**Impact.** No runtime effect; the store guard (`GameStore.swift:561-565`) is correct today. It is defence in depth: the human picker and the bot already exclude inspectors, so a visible leak would take two regressions, and neither filter has a test.

**Solution.** Use 9 players. Add `XCTAssertEqual(inspectors.count, 2)` and `guard inspectors.count >= 2 else { return }`, then assert without the `if`. Also add a test that `BotDecisionService.chooseInspectorTarget` never returns an inspector.

**Risk.** None.

#### PA-96 · No test guards the heartbeat fan-out or the "own seat only" read in `getSessionView`

**Severity:** Low (auditor: Medium; verified: Low) · **Status:** Recommended · **Evidence:** Code-verified; fan-out size measured in PA-01 · **Effort:** S

**Location:** `convex/views.ts:24-32`, `convex/views.ts:13-22`, `convex/sessions.ts:167-178`, `tests/convex/sessions.test.ts:103-115`

**Problem.** Neither test suite measures or bounds the main runtime cost, heartbeat fan-out (PA-01). The comment at `views.ts:30` ("Only the caller's own seat is read, so other players' heartbeats don't re-run this") states an invariant that nothing protects. If `getSessionView` were moved onto `loadMember`, it would silently join the fan-out.

**Evidence.** No `measure`, `XCTMetric` or vitest bench anywhere. The heartbeat tests (`sessions.test.ts:103-115`) check only the field update and host-claim staleness. Measured in PA-01: 136 query re-runs per 5 s at 8 humans and 741 at 19, which matches `(2H+1)·H/5` per second.

**Impact.** No direct runtime effect. A future change that adds per-seat work or widens a read set would multiply an already large re-run count, and nothing would catch it. The verifier estimates about 49k query executions in a 30-minute game with 8 humans, mainly a function-call quota concern.

**Solution.** Add one convex-test case: user B heartbeats, then deep-compare user A's `getSessionView` and `getRoundState` results before and after. This guards results, not read sets; record a one-time baseline from Convex insights for the read sets. The real fix is PA-01: move presence out of the range `getRoundState` reads, and keep `last_heartbeat` available for `checkHost` and `nextHost`. Skip a dev-deployment bench and simulator `measure` blocks, which are noisy and need DI that does not exist yet.

**Risk.** None for the test.

#### PA-97 · Live-test waits leave about 3.5 s of margin over one dropped first value, and timeouts do not show subscription state

**Severity:** Low · **Status:** Needs Further Investigation · **Evidence:** Code-verified (timing); drop rate not measured · **Effort:** S

**Location:** `mafia_managerTests/ConvexIntegrationTests.swift:163-169`, `Core/Multiplayer/Services/SubscriptionSupervisor.swift:30`, `Core/Multiplayer/Services/SubscriptionSupervisor.swift:87-124`, `Core/Multiplayer/Store/MultiplayerGameStore+Connection.swift:19-40`

**Problem.** According to SubscriptionSupervisor's own header, ConvexMobile can drop a first value. Recovery takes `firstValueTimeout` (15 s) plus a 0.8–1.2 s backoff. `waitUntil` allows 20 s. Tests cannot shorten the timeout: it is a `static let`, and `startSubscriptions` always uses the default sleep. The timeout message names only the condition.

**Evidence.** One drop recovers in about 15.8–16.2 s plus a round trip, and two drops take at least 30.8 s. Only the three first session-view waits (`:42`, `:103`, `:123`) depend on this; player-list waits self-heal through the 5 s heartbeat. Each run creates 15 supervisors, not 9.

**Impact.** Opt-in live suite only. One drop still passes. Two drops, or one plus more than 3.5 s of extra latency, give an unexplained timeout. The suite is recorded as passing, and no flake has been observed. To check: count "No first value; resubscribing" lines across about 20 live runs.

**Solution.** On the test side, append each store's `subscriptions.map(\.status)` to the timeout message, and give the three first-snapshot waits about 35–40 s. Optionally pass a label into `SubscriptionSupervisor` so its log names the query. A DEBUG-settable timeout is acceptable; a store-level timing API is more than this needs.

**Risk.** None for production.

#### PA-98 · Two `currentRoundId` tests would hang the run instead of failing if the wait regresses, because there is no `.timeLimit`

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `mafia_managerTests/Multiplayer/MultiplayerStoreTests.swift:127-148`, `Core/Multiplayer/Store/MultiplayerGameStore.swift:278-285`, `mafia_managerTests/Multiplayer/BotDirectorTests.swift:147-149`, `mafia_managerTests/AccountRestorationTests.swift:104-106`

**Problem.** The auditor flagged tests that sync by counting `Task.yield` or sleep-polling as flaky under load. The verifier showed that every chain stays on the main actor's queue, so it is deterministic. The real hazard is narrower. `currentRoundId()` waits on `$sessionView.dropFirst().values` with no timeout, and the tests await it with no suite time limit. If someone removed `if sessionId == nil { break }` (`:282`), `leavingStopsWaitingForARound` would hang instead of failing, and it is the test meant to catch exactly that.

**Evidence.** A grep for `timeLimit` matches only `ConvexIntegrationTests.swift:18`. The parked continuations in BotDirector and SubscriptionSupervisor run in tasks no test awaits, so at worst they leak. The AccountRestorationTests poll is capped at about 1 s.

**Impact.** No app effect and no CI. The risk is a hung local `tuist test`.

**Solution.** Add `.timeLimit(.minutes(1))` to `MultiplayerStoreTests`. Do not cancel `waiting` on a timeout: cancellation throws `SessionError.noActiveSession`, which the leave test expects, so a regression would pass. Race it against a sleep and call `Issue.record` instead. Keep `settle()`.

**Risk.** None; test-only.

#### PA-99 · Live tests leave guest users, cancelled rooms and a Clerk dev user on the dev backends every run

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified; dev table counts measured but not attributable to tests · **Effort:** S

**Location:** `mafia_managerTests/ConvexIntegrationTests.swift:136-142`, `mafia_managerTests/ConvexIntegrationTests.swift:173-194`, `mafia_managerTests/ClerkAccountIntegrationTests.swift:21-38`, `convex/lib/transitions.ts:62-77`

**Problem.** Each ConvexIntegrationTests run creates 5 new guest users and 3 rooms. `withCleanup` only cancels the rooms. Cancelling deletes seats, actions and tentatives but keeps the `game_sessions` row. Each ClerkAccountIntegrationTests run signs up a new `mafia-native-<uuid>+clerk_test@example.com` user, whose Convex account row stays too. Teardown removes only stats rows and signs out. `convex/` has no cron or scheduler.

**Evidence.** Measured dev counts: 330 users and 224 sessions, 207 of them cancelled. Normal dev use and manual QA leave rows too, so these counts cannot be attributed to the tests. The team already notes the leftovers in SESSION_CHANGES.md:263 and :620-623.

**Impact.** Dev only, with no runtime cost. The leftovers clutter the dashboard and skew dev counts. They also creep toward a Clerk dev-instance user cap (about 500 per the verifier, unconfirmed).

**Solution.** Add an env-gated `internalMutation`, `testing:purgeQa`, and run it against dev with `npx convex run`; the iOS tests cannot call an internal function. It deletes `QA ` guests, test-pattern accounts and their cancelled rooms in `.take(n)` batches. Clean up Clerk users with a local script; never put the secret key in the test bundle. PA-23 covers production data lifecycle.

**Risk.** A purge that reaches production unguarded is dangerous. Keep it internal and env-gated, and filter strictly on QA markers.

#### PA-100 · Rules and error strings duplicated in Swift and TypeScript have no cross-language parity test

**Severity:** Low · **Status:** Recommended · **Evidence:** Code-verified · **Effort:** S

**Location:** `mafia_managerTests/Multiplayer/MultiplayerStoreTests.swift:169-181`, `Core/Multiplayer/Store/BotDirector.swift:14-19`, `convex/lib/rules.ts:69-74`, `Core/Gameplay/Store/GameStore.swift:488-504`

**Problem.** The role table, the target rules (`canTarget` mirrors `validateGameAction`) and the server error texts the client matches exactly all exist in both languages, and each side tests only itself. `assignmentsCoverEverySeatWithServerRoleCounts` compares `makeAssignments` with `GameStore.roleDistribution`, which `makeAssignments` uses itself (`HostPhases.swift:18`). Six strings are separate Swift literals: four round-closing messages, `signInMessage` (= `E.AUTH`) and `guestNotFound` (= `E.GUEST_NOT_FOUND`).

**Evidence.** `MultiplayerStoreTests.swift:177` `let expected = GameStore.roleDistribution(for: count)`. `BotDirectorTests.swift:186` iterates `roundClosedMessages` itself. The only link between the tables is the comment `// GameStore.swift 488-504.` at `rules.ts:69`. Everything matches today.

**Impact.** No defect today, but drift would ship unnoticed. A role-table drift fails every multiplayer start at the affected counts. A reworded `E.AUTH` stops unrecognised players from leaving or ending a game. A reworded `E.GUEST_NOT_FOUND` retries the guest merge on every launch.

**Solution.** Add `tests/fixtures/rules-parity.json` with role counts for 4–19 players, target-rule cases and all six messages. Load it from vitest and from a parameterised Swift Testing test. Add it as a test-target resource in `Project.swift` and regenerate with Tuist. Leave win conditions out until PA-13 is decided. Structured error codes are a later step and need `BackendError` to accept both payload shapes first.

**Risk.** None for the fixture.


---

## 5. Implemented improvements

**No code changes, by request.** No source, configuration, project or backend file was changed, and nothing was deployed.

**One clean-up at your request, after the audit:** I deleted the 45 iCloud duplicate files, the 3 empty duplicate folders and `.git/index 2`. PA-03 is now Partially implemented. Every other finding is **Recommended** or **Needs Further Investigation**.

The experiments behind the measurements ran only on throwaway copies outside the repo. They are evidence, not changes:

| Experiment (scratch copy only) | Purpose | Outcome |
|---|---|---|
| HEAD with `ClerkKitUI` removed from `Project.swift` | A/B build time and size | −45–54% clean-build wall time, −52–59% CPU, IPA −4.6%, build succeeds (PA-18) |
| Working-tree copy with the ` 2` duplicates, `tuist generate` and build | Confirm the duplicate-file break | 316 error lines (PA-03) |
| Instrumentation: a body-evaluation counter, microbenchmark tests, a re-render bench, a launch UI test, a `convex-test` payload probe, a layout probe | Produce the numbers in §3 | See §3 |
| Bare SwiftUI control app | Launch, memory and thread baseline | §3.3 |
| Second pass: HEAD in Release and Debug; an empty SwiftUI app with and without single framework imports; a stripped copy; automated solo games | Instruments, `leaks`, `heap`, `vmmap` and library-load measurements | §3.8, PA-101–PA-103 |

---

## 6. Remaining opportunities: prioritized roadmap

Ordering principle: first unblock development, then make multiplayer survive real sessions, then cut backend cost, then fix rule correctness, and finally hygiene. Effort is S (hours), M (a day or two) or L (more).

- "Measured" benefits come from the A/B runs in §3 and §7.
- "Modeled" benefits are estimates.

### Phase 0: today, about an hour, no product risk

| # | Action | Findings | Benefit | Effort |
|---|---|---|---|---|
| 1 | ~~Delete the 45 byte-identical ` 2` copies, the empty ` 2` dirs and `.git/index 2`~~ (done on request). Rebuild the stale dependency cache: `rm -rf Tuist/.build && tuist install && tuist generate`. Re-clone outside `~/Documents`, e.g. `~/Developer`. Drop the stale in-repo `DerivedData/` and root build logs | PA-03, PA-102, PA-17, PA-89 | Builds work again (measured: 316 errors before; 0 after the deletion plus cache rebuild). Stops recurrence. Frees about 0.6 GB of synced artifacts | S |
| 2 | Remove `.external(name: "ClerkKitUI")` from `Project.swift`, then `tuist install && tuist generate` | PA-18 | Measured: clean Debug −45–54% wall, −52–59% CPU; IPA −4.6%; no runtime change | S |
| 3 | Lock iPhone to portrait in `Project.swift` (keep the iPad key) | PA-15 | Measured: the landscape vote list goes from 0 pt to usable. Removes off-screen forward buttons | S |
| 4 | Exclude x86_64 for dependency projects in `Tuist/Package.swift` | PA-80 | About 129 CPU-s less per clean Release-simulator build (verifier measurement) | S |

### Phase 1: before multiplayer meets real groups (reliability)

| # | Action | Findings | Benefit | Effort |
|---|---|---|---|---|
| 5 | Host "Waiting for…" list with **Remove**, room code visible in-game, host may start the night before every role is confirmed. Then handle departed seats at resolution and re-validate reused bot targets | PA-02, PA-39, PA-50 | Removes the main way a session dies permanently | M |
| 6 | Pause only on `.background` and resume only after a real background. Longer lobby host threshold and reclaim via `returnToLobby`. Keep the screen awake during games. Judge staleness by server time. Single-flight `ensureValidSession` | PA-05, PA-06, PA-40, PA-33, PA-41 | Stops host controls hopping on glances, auto-lock and texting the room code | S–M |
| 7 | Surface `watchWebSocketState()` as a reconnect banner. Bounded, cancellable one-shot queries. Mutation timeouts that report "still sending" rather than "failed". Generation token for create/join cancel. In-flight and error states on host buttons and votes | PA-07, PA-08, PA-09, PA-36, PA-37, PA-49 | Users see outages instead of frozen screens. No hidden orphaned rooms | M |
| 8 | Show load errors instead of empty states. Restore the submitted vote on re-mount. Auto-finish the night for citizen and eliminated hosts too | PA-54, PA-47, PA-38 | Fewer "lost data" scares and fewer waits on a host tap with no cue | S |

### Phase 2: backend cost (ship backend and app in lockstep)

| # | Action | Findings | Benefit | Effort |
|---|---|---|---|---|
| 9 | Move presence into a `session_presence` table. Add a tiny host-presence query. Drop `last_heartbeat`/`is_online` from the roster projection. Make snapshot models `Equatable` and skip unchanged assignments. Guard `isHostOffline` writes | PA-01, PA-10, PA-34, PA-22 | Modeled at 8 humans: idle query re-runs about 136 → 8 per 5 s, and roster pushes on heartbeats → 0. Measured today: 10 of 10 identical snapshots publish; the target is 0 | M |
| 10 | Cache the guest-proof hash in memory (measured 259 µs Keychain + SHA-256 per request on the main actor). Remove the unread `setReady` calls. Narrow `getRoundState` reads per viewer. Skip same-target tentative writes. Combine record and resolve into one transaction. Optionally batch bot submissions | PA-32, PA-35, PA-20, PA-24, PA-31, PA-21, PA-26 | Second-order fan-out and round-trip cuts | S–M |
| 11 | Launch-time contract check (`health:check` + minimum client contract), golden JSON contract fixtures decoded in Swift, `returns` validators on `views:*`, terminal handling of decode failures | PA-30, PA-11 | Version skew becomes a clear "update the app" message instead of an endless "Reconnecting…" | M |
| 12 | Add a test proving another player's heartbeat leaves `getSessionView`/`getRoundState` results unchanged. Watch function counts in the dashboard during an idle 4-device lobby (model: about 430 executions/min) | PA-96 | Locks in the gain and validates the cost model | S |

### Phase 3: game-rule correctness

| # | Action | Findings | Benefit | Effort |
|---|---|---|---|---|
| 13 | Count human Mafia votes first on the server, so bots cannot outvote a human majority | PA-12 | Correct kills in mixed human and bot Mafia teams | S |
| 14 | Pick one post-night win rule. Align `GameStore`, `rules.ts`, both test suites, the Intro text and the docs. Share a parity fixture between vitest and Swift tests | PA-13, PA-100 | The same position gives the same result in both modes | S |
| 15 | Arm the all-bot Mafia timer only after "Start Night". Make solo night timers cancellable and guard them on `isGameOver`. Delete the role-blind random bot vote fallback | PA-14, PA-58, PA-51 | Stops the hidden-role leak and post-End-Game state changes | S–M |

### Phase 4: data integrity and backend hygiene

| # | Action | Findings | Effort |
|---|---|---|---|
| 16 | One idempotent `stats:recordGame` batch driven by a small persisted outbox outside `GameState`. Skip bot seats | PA-04, PA-57 | M |
| 17 | Cron sweeper for abandoned rooms, finished seats, old sessions and ownerless guests. Auto-resolve guest-merge seat conflicts in non-live rooms | PA-23, PA-29 | M |
| 18 | Index clean-up; merge should patch only live rooms; cap `merged_guest_digests` | PA-25, PA-27, PA-28 | S |

### Phase 5: engineering system

| # | Action | Findings | Effort |
|---|---|---|---|
| 19 | CI: an Ubuntu job (`vitest` plus type-checking the tests via a new `tests/tsconfig.json`) and a macOS job (`tuist test` with selective testing off). Gate `convex:deploy` on the tests | PA-19, PA-88 | M |
| 20 | Guard the test host so unit tests don't boot Clerk/Convex. Isolate `Persistence`. Add a service and clock seam to the multiplayer store. Add `.timeLimit` to async suites. Fix the vacuous inspector test | PA-92, PA-93, PA-98, PA-95, PA-94, PA-97, PA-99 | M |
| 21 | Clear the 27 build warnings (the isolated-conformance warning first). Stage strict concurrency. Pin Tuist, Node, Xcode, clerk-ios and convex-swift ranges. Untrack the `bypassPermissions` default and the dead Supabase MCP entries. Restore a build-time config check. Delete stale pre-Tuist scripts. Fix the asset catalog. Declare collected data in the privacy manifest | PA-91, PA-81, PA-83, PA-84, PA-87, PA-56, PA-82, PA-85, PA-90 | S–M |

### Phase 6: UI polish, accessibility and launch

| # | Action | Findings | Effort |
|---|---|---|---|
| 22 | Setup list: stable row ids and Dynamic-Type-safe height. Same for the group editor | PA-16, PA-59, PA-66 | S–M |
| 23 | `.layoutPriority(1)` on the vote list and night role section. `safeAreaInset` lobby footer. Keyboard-safe landscape Setup. Wrapping teammate pills. Clamped intro pager | PA-75, PA-76, PA-77, PA-78, PA-64 | S |
| 24 | Move the sound warm-up (measured at 48–54 ms of main-thread launch time) from launch to the solo night, setting the audio category first. Keep audio-interruption handling. Dark launch background | PA-55, PA-72, PA-86 | S |
| 25 | Library screens: keep data while refreshing and apply mutation results locally. Drop the redundant Clerk refresh for guests at launch | PA-53, PA-52 | S–M |
| 26 | Remove the nested `NavigationStack` and the deprecated hidden links. Delete about 650 lines of unreachable legacy views. Split `SetupView.body` (1.08 s to type-check). Lenient decoding of saved games | PA-62, PA-60, PA-73, PA-74, PA-65 | M |
| 27 | iPad: readable-width caps and adaptive grids, or drop iPad from the target | PA-79 | M–L |
| 28 | Game Over: render the log as lazy lines, move the card shadow to a fixed-size shape, compute the log text once | PA-103, PA-67 | S |

The remaining Low items are small, independent clean-ups that can be done whenever their files are touched:
- PA-42–PA-46
- PA-48
- PA-61
- PA-63
- PA-67–PA-71

### Needs further investigation before acting

| Finding | What to measure or check first |
|---|---|
| PA-26 | Whether point seat reads in per-player mutations reduce conflicts. Insights show 0 OCC today, so check the dashboard under load first |
| PA-44 | Record the phase transition (or step it slowly) to confirm the outgoing view really shows the next phase's content |
| PA-66 | Reproduce the stale index-binding crash in the group editor with rapid deletes |
| PA-67 | Profile shadow cost on a device with Instruments before restyling |
| PA-72 | Time `AVAudioSession` activation on a device, and test interruption recovery |
| PA-97 | Measure the live suite's first-value drop rate before lengthening its waits |
| PA-101 | Run the App Launch template on a physical iPhone and compare with an empty app, to see whether AuthenticationServices' ~1,000 extra libraries matter on a device |
| PA-103 | On a device, record Allocations + VM Tracker and Hitches across Game Over → Play again to attribute the 95 ms commit and the ~37 MB spike |
| Cross-cutting | On a physical iPhone, take the measurements the simulator cannot provide: SwiftUI, Hitches, Network, Power and exportable Allocations. Run one real 4–8-device session and compare Convex function counts and database I/O with the PA-01 model |

### Considered and not recommended

- **Treat stale heartbeats as automatic abstention inside readiness (PA-02).** Auto-lock would cost players their turn. It would also trigger the host's auto-finish, and target-less Mafia rows fall back to killing the first valid target.
- **Emit a constant `last_heartbeat` for old clients while migrating presence (PA-01).** Old clients would mark the host offline and spam `claimHost`. Ship in lockstep instead.
- **Merge the three views into one `views:getGame` query.** It gives atomic snapshots, but a single tentative tap would then re-send the whole snapshot (about 10 KB). Prefer equality guards plus the presence split.

---

## 7. Final verification

Nothing was implemented, so there is no before/after for code changes. These are the checks I ran on the code as it stands, and the A/B experiments that size the top recommendations.

**Tests and type-check (pristine `HEAD` copy):**
- Unit tests: **105 run, 101 passed, 4 skipped, 0 failed**. The skips are opt-in live suites; one Clerk integration test is skipped by design.
- Backend `vitest run`: **47/47 passed**.
- `tsc --noEmit -p convex/tsconfig.json`: **pass**.
- I did not run the live Convex integration suites (`TEST_RUNNER_CONVEX_INTEGRATION=1`), to avoid writing to the dev deployment.

**Build status:**

| Build | Result |
|---|---|
| Debug (simulator), clean | **Pass**, 27 warnings |
| Release (generic iOS), with link map | **Pass** |
| Release (simulator, dev-backend overrides) | **Pass** |
| Working tree after `tuist generate`, at audit time | **Fail**, 316 error lines (PA-03) |
| Cleaned working tree (copy), after deleting the duplicates and rebuilding `Tuist/.build` | **Pass**, 0 errors, 0 duplicate references |
| Second pass, Xcode 27.0 release: Release and Debug (simulator) | **Pass** |

**Second-pass checks:**
- `leaks`: no app leaks, at the intro screen or after 3 full games.
- Memory: no growth across games (§3.8).
- Instruments: Time Profiler, App Launch and Core Animation Commits run on the simulator.

**Benchmark comparisons available today:**

| Comparison | Baseline | Variant | Delta |
|---|---|---|---|
| Clean Debug build (HEAD vs no ClerkKitUI), pair 1 | 55.3 s wall / 261 s CPU | 30.7 s / 127 s | −45% / −51% |
| Clean Debug build, pair 2 (heavier load) | 120.1 s / 469 s CPU | 55.0 s / 191 s | −54% / −59% |
| Zipped IPA | 5,272,245 B | 5,028,318 B | −4.6% |
| Cold launch (app vs bare SwiftUI app) | 2.469 s (control) | 2.752 s (app) | +0.28 s mean (≈+0.4 s median) |
| First-screen footprint | 17 MB (control) | 35–48 MB (app) | +18–31 MB |
| System images loaded at launch (second pass) | 596 (empty app) | 1,603 (app) | +1,007, all from AuthenticationServices (PA-101) |
| Loader CPU per simulator launch (second pass) | 448–596 ms (empty app) | 1,325–1,688 ms (app) | about +1 s (PA-101) |
| Redundant push re-render cost (12 players) | ≈1.3 ms idle iteration | 2.6–3.4 ms | +1.4–2.0 ms per push |

**Expected effect of the top recommendations.** These are modeled, not measured, because nothing was implemented:
- **PA-01 presence table:** idle query re-runs per room drop from H·(2H+1) to about H tiny `getHostPresence` re-runs per 5 s. At 8 humans, roughly 136 → 8 executions per 5 s, and roster pushes on heartbeats go to zero.
  - Verify with the Convex dashboard function counts during a 5-minute idle lobby with 4 devices. The current model predicts about 430 query executions per minute.
- **PA-10 / PA-34 equality guards:** identical snapshots should fire 0 `objectWillChange`, against 10 out of 10 measured today.
  - The same microbenchmark can verify this.
- **PA-55 lazy audio warm-up:** removes the measured 48–54 ms from the main thread at launch, and the audio threads from the first screen.
  - Re-measure with the same suspended-launch Time Profiler run (§3.8), ideally on a device.

---

## 8. Limitations and unverified assumptions

1. **Simulator only.** All runtime numbers come from an iOS 27.0 simulator on an Apple-silicon Mac. Real phones have slower CPUs and real radios.
   - Treat µs/ms costs as lower bounds.
   - Treat energy and radio effects as unmeasured.
2. **Instruments on the simulator only.** The Xcode 27 beta hung on every `xctrace` recording. On the Xcode 27.0 release, Time Profiler, App Launch and Core Animation Commits work, and §3.8 uses them.
   - **No data on the simulator:** SwiftUI, Hitches and Network.
   - **Not exportable from the command line:** Allocations.
   - **Not run:** Energy/Power.
   - Full malloc logging did not engage, so the Game Over memory spike is measured but not attributed (PA-103).
3. **Noisy wall clock.** The Mac was also running audit agents. The control app's launch RSD was 12.7% with one 3.24 s outlier. CPU-seconds and paired A/B runs are the reliable numbers.
4. **Billing is modeled.** The cost model combines code-derived fan-out, measured payload sizes, and Convex's `limits.mdx` from the convex-backend source, plus Convex staff statements on their Discord.
   - I could not load the live pricing page.
   - Which Convex plan the project is on is unknown.
   - Usage-dashboard numbers were not checked.
5. **No real multiplayer session.** Fan-out counts come from code and `convex-test`. They were not observed across several devices on a real network. Per-mutation latency is estimated from RTT (42 ms ICMP; ≈216–282 ms HTTPS) and older dev logs (10–30 ms server time).
6. **Small data.** Prod tables are essentially empty, and dev has 224 sessions and 330 users. Auditors' ad-hoc `runOneoffQuery` calls hung, so their data claims were rechecked with an offline harness and my table counts.
7. **Layout probes cover one device.** They were run on iPhone 17 at default text size only. iPhone SE, iPad, 19-player rooms and accessibility text sizes were not rendered (PA-16, PA-75, PA-77–PA-79 remain partly inferred).
8. **Third-party behaviour comes from source reading.** These facts come from reading pinned public sources, not from runtime traces:
   - convex-rs re-broadcasts all subscription values on every transition;
   - Authenticate re-runs every query;
   - there is no mutation timeout at any layer;
   - Convex's bundler skips paths containing spaces.

   A permission rule blocked me from reading `node_modules/convex/dist`. An auditor read the bundler source; I did not verify that part myself.
9. **Denied commands.** Two shell commands were denied by your permission settings and not retried: a hardware `sysctl` query and a directory listing of generated project folders. The exact Mac model is therefore not recorded.
10. **Trigger frequencies are estimates.** How often players hit things like a disconnect stall, landscape rotation or a host hop is estimated. There is no analytics data.
11. **Static-audit coverage.** 302 files were read across 16 audit and gap agents. The completeness critic named thin areas: memory/leaks, energy and xcconfig review. The second pass covered memory and leaks for solo play; energy and the xcconfig review remain thin.
12. **Automation artifacts.** The second pass drove the app through accessibility (AXe). That makes UIKit load its accessibility bundles and answer accessibility queries, so the gameplay CPU numbers are upper bounds. Only solo screens were driven.

---

## Appendix A · Finding index

| ID | Finding | Severity | Status | Evidence | Effort |
|---|---|---|---|---|---|
| PA-01 | Heartbeats rewrite the roster rows that two subscriptions read, so presence re-runs queries quadratically and pushes full rosters every 5 s | High | Recommended | Code-verified | M |
| PA-02 | A silently disconnected player stalls the night or vote forever: no timeout, no in-game removal, no "waiting for" view | High | Recommended | Code-verified | M |
| PA-03 | iCloud conflict copies (`* 2.swift`) are matched by Tuist's source globs, so the working copy no longer builds | High | Partially implemented | Measured | S |
| PA-04 | Game-end stats sync runs per player, is not idempotent, is tied to the view and is never retried | Medium | Recommended | Code-verified | M |
| PA-05 | Treating `.inactive` as background pauses the heartbeat and re-authenticates on every glance | Medium | Recommended | Code-verified | S |
| PA-06 | The host role moves to another player after about 15 s in the background, with no way to take it back | Medium | Recommended | Code-verified | S |
| PA-07 | Network loss is invisible in multiplayer, and mutations never time out | Medium | Recommended | Code-verified | M |
| PA-08 | One-shot Convex queries and mutations have no timeout or cancellation, so screens spin while offline | Medium | Recommended | Code-verified | M |
| PA-09 | Cancel during an in-flight create or join leaves a hidden live session and an orphaned seat | Medium | Recommended | Code-verified | S |
| PA-10 | Three snapshots are applied separately with no equality check, causing redundant publishes and torn frames | Medium | Recommended | Measured | S |
| PA-11 | Nothing ties server JSON shapes to the Swift decoders, and a decode failure retries forever | Medium | Recommended | Code-verified | M |
| PA-12 | Mafia bots lock onto the first human's pick and can outvote a human majority via the earliest-row tie-break | Medium | Recommended | Code-verified | S |
| PA-13 | Solo and multiplayer use different win conditions after a night, and each mode's tests pin its own rule | Medium | Recommended | Code-verified | S |
| PA-14 | All-bot Mafia timer skips the "close your eyes / Start Night" gate and shows that every Mafia is a bot | Medium | Recommended | Code-verified | S |
| PA-15 | Template-default iPhone landscape pushes the only forward control of core-flow screens off-screen | Medium | Recommended | Measured | S |
| PA-16 | SetupView's fixed-height, non-scrolling player list clips rows at large Dynamic Type sizes | Medium | Recommended | Code-verified | S |
| PA-17 | Repo lives in iCloud-synced `~/Documents`, so large git operations create conflict copies that break the build | Medium | Recommended | Measured | M |
| PA-18 | Unused ClerkKitUI dependency costs about half of each clean build and ships 0.9 MB of dead resources | Medium | Recommended | Measured | S |
| PA-19 | No CI for build, typecheck or tests, and `convex:deploy` ships to production without running backend tests | Medium | Recommended | Code-verified | M |
| PA-20 | `getRoundState` reads the whole roster, all round actions and all tentatives for every viewer, then filters | Low | Recommended | Code-verified | S |
| PA-21 | Bots submit one mutation each, so a bot burst costs one commit and one `getRoundState` wave per bot | Low | Recommended | Code-verified | M |
| PA-22 | `is_online` is never written false, so the lobby's online dot is always green for human players | Low | Recommended | Code-verified | S |
| PA-23 | No data lifecycle: abandoned rooms, seats, actions and orphaned guest users are never cleaned up | Low | Recommended | Measured | M |
| PA-24 | Same-target taps and re-submits always rewrite their row and re-run every member's `getRoundState` | Low | Recommended | Code-verified | S |
| PA-25 | Redundant prefix indexes and unused indexes in `schema.ts` add write overhead | Low | Recommended | Code-verified | S |
| PA-26 | `submitAction` and `setTentativeSelection` read the whole roster when they need two or three seats | Low | Needs Further Investigation | Code-verified | S |
| PA-27 | Guest merge patches every session the guest ever hosted, including cancelled rooms | Low | Recommended | Code-verified | S |
| PA-28 | `merged_guest_digests` grows without bound on the account document | Low | Recommended | Code-verified | S |
| PA-29 | A guest-merge seat conflict, even in an old finished room, fails on every launch with no actionable message | Low | Recommended | Code-verified | S |
| PA-30 | The app never checks the backend API contract; old builds will fail with generic errors after a bump | Low | Recommended | Code-verified | S |
| PA-31 | Finish Night is two serial host mutations, adding a round trip and an extra invalidation wave to every night | Low | Recommended | Code-verified | S |
| PA-32 | Every Convex request reads the Keychain and hashes the guest secret on the main actor | Low | Recommended | Measured | S |
| PA-33 | Each foreground in a multiplayer session runs `ensureValidSession` twice concurrently, with no coalescing | Low | Recommended | Code-verified, including the pinned Clerk and Convex package sources | S |
| PA-34 | Coarse `ObservableObject` store republishes every heartbeat-only `players` change to all multiplayer views | Low | Recommended | Measured | S |
| PA-35 | Night actions and votes send a `setReady` write that nothing in night or voting reads | Low | Recommended | Code-verified | S |
| PA-36 | Reveal Deaths, Start Voting and Continue to Night drop mutation errors with `try?` | Low | Recommended | Code-verified | S |
| PA-37 | Non-host vote rows stay tappable during submit, so "You voted for X" can name a player other than the one recorded | Low | Recommended | Code-verified | S |
| PA-38 | Citizen hosts get no night auto-finish and are told to wait while the table waits for their tap | Low | Recommended | Code-verified | S |
| PA-39 | Votes and night targets on a seat that left mid-game still count, so that round loses its elimination | Low | Recommended | Code-verified | M |
| PA-40 | Host-offline check compares the device clock with server-written heartbeat times | Low | Recommended | Code-verified | S |
| PA-41 | Each Clerk token refresh re-authenticates Convex twice, the second time with an identical token | Low | Recommended | Code-verified through the vendored provider, clerk-ios 1.1.1, convex-swift 0.8.1 and convex-rs sources | S |
| PA-42 | `identityRevision` bumps on an unchanged identity and restarts all three multiplayer subscriptions | Low | Recommended | Code-verified | S |
| PA-43 | Derived player collections are rebuilt repeatedly per body with linear and O(N²) lookups | Low | Recommended | Code-verified | S |
| PA-44 | Outgoing phase views re-render against the new phase payload during their 0.3 s removal transition | Low | Needs Further Investigation | Inferred | S |
| PA-45 | Tied vote-result rows are ordered differently on each device | Low | Recommended | Code-verified | S |
| PA-46 | Vote reveal schedules its flip sound and haptic with uncancellable `asyncAfter` timers | Low | Recommended | Code-verified | S |
| PA-47 | Voting view does not restore an already-submitted vote after a relaunch and rejoin | Low | Recommended | Code-verified | S |
| PA-48 | Resume can restart the heartbeat loop after the session was cleared during the token refresh | Low | Recommended | Code-verified | S |
| PA-49 | Create/join discards the returned room code and pushes a bare spinner, with a possible torn 0-player frame | Low | Recommended | Code-verified | S |
| PA-50 | A reused mafia-bot target is never re-validated, so a mid-night leave can stall the night until End Game | Low | Recommended | Code-verified | S |
| PA-51 | Bot vote fallback fires on any non-closing error and picks a role-blind random seat | Low | Recommended | Code-verified | S |
| PA-52 | Cold-start restore sends a redundant Clerk refresh for guests and writes the user row on every launch | Low | Recommended | Code-verified | M |
| PA-53 | Library screens refetch with a full-screen spinner on every visit and after every edit | Low | Recommended | Code-verified | S |
| PA-54 | Player Stats and the Setup load sheets show empty states when a load fails | Low | Recommended | Code-verified | S |
| PA-55 | Sound warm-up builds four AVAudioPlayers on the main thread before the first frame of every launch | Low | Recommended | Measured | S |
| PA-56 | Missing or wrong backend config fails only at launch since the build-time guard was removed | Low | Recommended | Code-verified | S |
| PA-57 | Solo stats sync writes bot seats ("Bot 1"…"Bot N") as player_stats rows | Low | Recommended | Code-verified | S |
| PA-58 | Solo night timers and bot turns are not cancelled and can change an abandoned game after End Game | Low | Recommended | Code-verified | M |
| PA-59 | Setup player rows use index identity, so deleting a row animates the wrong row and can misplace focus | Low | Recommended | Code-verified | M |
| PA-60 | About 650 lines of unreachable legacy solo views and several dead APIs are still compiled | Low | Recommended | Code-verified | S |
| PA-61 | RootView observes an AuthStore it never reads, and NightWakeUpView holds a class-typed service field | Low | Recommended | Code-verified | S |
| PA-62 | Nested NavigationStack on the mode-selection screen, with deprecated hidden links carrying the screen's modifiers | Low | Recommended | Code-verified | M |
| PA-63 | Sound assets are AAC audio in M4A containers but named `.wav` | Low | Recommended | Measured | S |
| PA-64 | Intro screen CTA buttons overflow their fixed 56 pt row at large text, and the pager height can go negative | Low | Recommended | Code-verified | S |
| PA-65 | `Persistence.reset()` leaves the pending debounced save running, and backgrounding writes the state twice | Low | Recommended | Code-verified | S |
| PA-66 | Player name editors bind `TextField`s by array index and remove rows in place (Player Groups and solo Setup) | Low | Needs Further Investigation | Inferred | S |
| PA-67 | Shadows are drawn from whole composite views, and the button styles stack two shadows | Low | Needs Further Investigation | Inferred | S |
| PA-68 | Material blur is drawn over content that has already been removed (night transition and role-reveal screens) | Low | Recommended | Code-verified | S |
| PA-69 | Two declared animations never run: the bot-acting pulse and the GameOver confetti | Low | Recommended | Code-verified | S |
| PA-70 | Accessibility identifiers are built from labels with a regex on every render, and nothing reads them | Low | Recommended | Code-verified | S |
| PA-71 | Solo screens create a new haptic generator on every tap without calling `prepare()` | Low | Recommended | Code-verified | S |
| PA-72 | Sound warm-up runs on the main thread at launch, and the audio session is set up again after every `.inactive` | Low | Needs Further Investigation | Inferred | S |
| PA-73 | `SetupView.body` takes over a second to type-check, and the night wake-up screens repeat one block three times | Low | Recommended | Measured | M |
| PA-74 | Saved solo games can be lost silently on model changes: `load()` swallows decode errors and nothing shows them | Low | Recommended | Code-verified | S |
| PA-75 | Spacers around the multiplayer vote list and night target grid waste height; the predicted stall did not reproduce | Low | Recommended | Measured | S |
| PA-76 | Lobby footer space comes from a hard-coded spacer, so at accessibility text sizes the footer can cover the last player rows | Low | Recommended | Code-verified | S |
| PA-77 | In iPhone landscape with the keyboard up, SetupView's footer hides the name field and the guest "Start Playing" button sits under the keyboard | Low | Recommended | Code-verified layout | S |
| PA-78 | Mafia role reveal puts all teammate pills in one non-wrapping HStack, so long names break mid-word in large games | Low | Recommended | Code-verified | S |
| PA-79 | iPad runs stretched phone layouts with no size-class or readable-width handling | Low | Recommended | Code-verified | M |
| PA-80 | Release-simulator builds also compile every dependency for x86_64 | Low | Recommended | Measured | S |
| PA-81 | App builds in Swift 5 mode with minimal concurrency checking | Low | Recommended | Code-verified | M |
| PA-82 | Pre-Tuist helper scripts are stale but still advertised as the simulator workflow | Low | Recommended | Code-verified | S |
| PA-83 | Tuist, Xcode and Node versions and the Release build settings are not pinned | Low | Recommended | Code-verified | S |
| PA-84 | SwiftPM `from:` ranges let clerk-ios drift across breaking 1.x releases on the next dependency update | Low | Recommended | Code-verified | S |
| PA-85 | Asset catalogs reference a missing AccentColor, carry an unused icon PNG, and include a stray second catalog | Low | Recommended | Measured | S |
| PA-86 | Blank launch screen follows the system appearance, so light-mode users see a white frame before the dark UI | Low | Recommended | Code-verified | S |
| PA-87 | Tracked agent configs default to bypassPermissions, keep a dead Supabase entry with a public anon key, and run unpinned MCP servers | Low | Recommended | Code-verified | S |
| PA-88 | Backend tests in `tests/convex/` are never type-checked | Low | Recommended | Code-verified | S |
| PA-89 | Repo clutter: stale in-repo DerivedData, a restored vendored xcodeproj, root build logs, design binaries, diverged skill copies | Low | Recommended | Measured | S |
| PA-90 | Privacy manifest declares no collected data types, though the backend stores email, name, user ID and gameplay data | Low | Recommended | Code-verified | S |
| PA-91 | Clean Debug build emits 27 warnings, including an isolated-conformance warning on the mutation path | Low | Recommended | Measured | S |
| PA-92 | Unit tests run inside the full app, which boots Clerk and Convex and shares the real solo save file | Low | Recommended | Measured | M |
| PA-93 | Multiplayer host and connection paths have no unit tests and no seam for a fake `SessionService` or the 5 s ticker | Low | Recommended | Code-verified | M |
| PA-94 | Live tests switch a process-global guest proof, so retried subscriptions and background requests act as the wrong player | Low | Recommended | Code-verified | S |
| PA-95 | The solo "inspector cannot identify another inspector" test asserts nothing, because 8 players have one inspector | Low | Recommended | Code-verified | S |
| PA-96 | No test guards the heartbeat fan-out or the "own seat only" read in `getSessionView` | Low | Recommended | Code-verified | S |
| PA-97 | Live-test waits leave about 3.5 s of margin over one dropped first value, and timeouts do not show subscription state | Low | Needs Further Investigation | Code-verified | S |
| PA-98 | Two `currentRoundId` tests would hang the run instead of failing if the wait regresses, because there is no `.timeLimit` | Low | Recommended | Code-verified | S |
| PA-99 | Live tests leave guest users, cancelled rooms and a Clerk dev user on the dev backends every run | Low | Recommended | Code-verified | S |
| PA-100 | Rules and error strings duplicated in Swift and TypeScript have no cross-language parity test | Low | Recommended | Code-verified | S |
| PA-101 | AuthenticationServices, pulled in by ClerkKit, makes the app load about 1,000 extra system libraries at launch | Low | Needs Further Investigation | Measured | S |
| PA-102 | After the latest pull, `tuist generate` fails until the stale `Tuist/.build` dependency cache is rebuilt | Low | Recommended | Measured | S |
| PA-103 | The Game Over screen is the most expensive solo screen: a ~95 ms commit when it appears and a ~37 MB memory spike when it is left | Low | Needs Further Investigation | Measured | S–M |

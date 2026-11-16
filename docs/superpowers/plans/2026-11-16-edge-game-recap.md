# Morning EDGE Game Recap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Post a two-or-three-post EDGE tracking thread the morning after every tracked-team game.

**Architecture:** The daily scheduler enqueues `EdgeGameRecapWorker`, which fetches per-game EDGE payloads through `Nhl::EdgeClient`, hands them to a pure `EdgeRecap::GameData` normalizer and an `EdgeRecap::Formatter`, and enqueues the result through `RodTheBot::PostThread`. Missing data reschedules a bounded number of times.

**Tech Stack:** Rails 8.1, Sidekiq, Redis, Minitest, Mocha, VCR.

**Spec:** `docs/superpowers/specs/2026-11-16-edge-game-recap-design.md`

## Global Constraints

- All NHL requests go through `Nhl::EdgeClient`, `Nhl::GameClient`, `Nhl::ScheduleClient`; no HTTP in services or formatter.
- Player names come from `Nhl::PlayerDirectory.for_game(game_id)` via `name_with_number`.
- Entries are matched to the game by the game ID at the end of `gameCenterLink` (for example `/gamecenter/sea-vs-car/2026/11/14/2026020321`), never by date.
- Distances are imperial miles to two decimals; speeds are mph to two decimals; ice time is `M:SS` from seconds.
- Every post fits `RodTheBot::PostThread.content_limit`.
- No preseason posts.
- Run tests with `mise exec -- bundle exec rails test <path>`.

## Review Focus

- **Stale cache on retry:** a payload cached before the nightly batch must not hide data that has since landed. Recap fetches bypass the cache (Task 1, Task 4 test).
- **Same teams on consecutive nights:** the last-10 list holds two games against the same opponent; only the entry with the matching game ID is used (Task 2 test).
- **Opponent payload present but without this game:** the opponent line is omitted, not filled from another game (Task 2 test).
- **Skater missing from the game directory:** that skater's line is skipped and the next skater fills the top three (Task 3 test).
- **Game not played to a final (postponed, canceled, still live):** no post and no reschedule (Task 4 test).

---

### Task 1: EDGE client endpoint and cache bypass

**Files:**
- Modify: `app/services/nhl/edge_client.rb`
- Test: `test/services/nhl/edge_client_test.rb`
- Cassette: `fixtures/vcr_cassettes/edge_team_skating_distance_detail_12.yml`

**Interfaces:**
- Produces: `Nhl::EdgeClient.fetch_team_skating_distance_detail(team_id, game_id:, fresh:)`; every `fetch_*` method gains `fresh: false`. With `fresh: true` the request is made and the cache overwritten.

- [ ] **Step 1: Write failing tests**

```ruby
test "fetches team skating distance detail" do
  Nhl::EdgeClient.expects(:get_json).with("/edge/team-skating-distance-detail/12/20262027/2").returns({"skatingDistanceLast10" => []})
  assert_equal({"skatingDistanceLast10" => []}, Nhl::EdgeClient.fetch_team_skating_distance_detail(12, game_id: 2026020321))
end

test "fresh bypasses a cached response and replaces it" do
  Nhl::EdgeClient.expects(:get_json).twice.returns({"v" => 1}, {"v" => 2})
  with_memory_cache do
    Nhl::EdgeClient.fetch_team_skating_distance_detail(12)
    assert_equal({"v" => 2}, Nhl::EdgeClient.fetch_team_skating_distance_detail(12, fresh: true))
    assert_equal({"v" => 2}, Nhl::EdgeClient.fetch_team_skating_distance_detail(12))
  end
end

test "team skating distance detail lists recent games with splits" do
  VCR.use_cassette("edge_team_skating_distance_detail_12") do
    game = Nhl::EdgeClient.fetch_team_skating_distance_detail(12, season: 20262027, game_type: 2)["skatingDistanceLast10"].first
    assert_match %r{/\d{10}\z}, game["gameCenterLink"]
    assert game.dig("distanceSkatedAll", "imperial").positive?
    assert game.key?("toiEven")
  end
end
```

If the test environment's `Rails.cache` is a null store, `with_memory_cache` swaps in `ActiveSupport::Cache::MemoryStore` for the block; if an equivalent helper already exists in `test_helper.rb`, use it.

- [ ] **Step 2: Run** `mise exec -- bundle exec rails test test/services/nhl/edge_client_test.rb` — expect failures (undefined method, unknown keyword).
- [ ] **Step 3: Implement** — add `team_skating_distance_detail: ["team-skating-distance-detail", 6.hours]` to `ENDPOINTS`; add `fresh: false` and pass `force: fresh` to `Rails.cache.fetch`. Record the cassette once with `record: :once`.
- [ ] **Step 4: Run** the file again — expect pass.
- [ ] **Step 5: Commit** `Add EDGE team skating distance endpoint and cache bypass`.

### Task 2: `EdgeRecap::GameData`

**Files:**
- Create: `app/services/rod_the_bot/edge_recap/game_data.rb`
- Test: `test/services/rod_the_bot/edge_recap/game_data_test.rb`

**Interfaces:**
- Produces:

```ruby
RodTheBot::EdgeRecap::GameData.build(game_id:, team:, opponent:, shots:, speeds:, skaters:) # => Result or nil
Result = Data.define(:distance, :even, :power_play, :penalty_kill, :rank, :games, :opponent_distance, :skaters, :marks)
Skater = Data.define(:player_id, :miles, :seconds)
Mark   = Data.define(:kind, :player_id, :mph, :rank)   # kind is :shot or :speed
```

  - `team`, `opponent`: `team-skating-distance-detail` payloads (`opponent` may be nil).
  - `shots`: `team-shot-speed-detail` payload or nil (`hardestShots[]` with `player.id`, `shotSpeed.imperial`).
  - `speeds`: `team-skating-speed-detail` payload or nil (`topSkatingSpeeds[]` with `player.id`, `skatingSpeed.imperial`).
  - `skaters`: `{player_id => skater-skating-distance-detail payload}`.
  - `distance`, `even`, `power_play`, `penalty_kill`: miles as Float; a split is nil when its `toi*` is zero or absent.
  - `rank`: 1-based position of this game by `distanceSkatedAll` descending within `skatingDistanceLast10`; `games`: that list's size.
  - `skaters`: all skaters whose payload has the game, sorted by miles descending.
  - `marks`: shots then speeds, each ordered by `rank`, where `rank` is the 1-based index in the season list.
  - Returns nil when `team` is nil or its list lacks the game.

- [ ] **Step 1: Write failing tests** with a small `entry(game_id, miles, ...)` helper that builds a list entry. Cases and key assertions:
  - `"returns nil when the team list lacks the game"`
  - `"ranks the game among recent games"` — distances 45.0 (this game), 47.0, 44.0 → `rank == 2`, `games == 3`
  - `"uses the entry with the matching game id when the same opponent appears twice"` — two entries, different IDs, same date-agnostic link shape → distance of the matching one
  - `"reports situational splits and omits a situation with no ice time"` — `toiPP: 0` → `power_play` nil
  - `"reports the opponent distance only from the same game"` — opponent payload without the game → `opponent_distance` nil; with it → value
  - `"orders skaters by distance and drops those without the game"`
  - `"collects season marks from this game with their list rank"` — shots list where indexes 1 and 3 match → marks ranks `[2, 4]` kind `:shot`, followed by `:speed` marks
  - `"has no marks when shot and speed payloads are missing"` — nil payloads → `marks == []`
- [ ] **Step 2: Run** `mise exec -- bundle exec rails test test/services/rod_the_bot/edge_recap/game_data_test.rb` — expect `NameError`.
- [ ] **Step 3: Implement** `GameData.build`. Game ID is extracted with `link.to_s[/\d+\z/].to_i`.
- [ ] **Step 4: Run** — expect pass.
- [ ] **Step 5: Commit** `Add EDGE recap game data normalizer`.

### Task 3: `EdgeRecap::Formatter`

**Files:**
- Create: `app/services/rod_the_bot/edge_recap/formatter.rb`
- Test: `test/services/rod_the_bot/edge_recap/formatter_test.rb`

**Interfaces:**
- Consumes: `Result`, `Skater`, `Mark` from Task 2.
- Produces: `RodTheBot::EdgeRecap::Formatter.new(result:, names:, team_name:, opponent_name:, home:, limit: RodTheBot::PostThread.content_limit).posts # => Array<String>`; `names` responds to `call(player_id)` and returns a display name or nil.

- [ ] **Step 1: Write failing tests.** The full-thread test asserts these three strings exactly (result built from the values shown; `home: true`):

```text
⛸️ EDGE recap: Hurricanes vs. Kraken

Hurricanes skated 45.28 mi (7th most in their last 10 games)
Kraken: 44.93 mi

Even strength 39.58 · Power play 3.48 · Penalty kill 2.22
```

```text
⛸️ Most ice covered:

#19 K'Andre Miller: 3.08 mi in 21:41
#20 Sebastian Aho: 2.94 mi in 18:50
#53 Jackson Blake: 2.77 mi in 16:55
```

```text
📈 New on the Hurricanes' season top 10:

💥 #4 Shayne Gostisbehere: 91.98 mph shot (6th hardest)
💥 #26 Sean Walker: 91.32 mph shot (8th hardest)
⚡ #74 Jaccob Slavin: 22.37 mph (10th fastest)
```

  Further cases:
  - `"road game title"` — `home: false` → first line `⛸️ EDGE recap: Hurricanes at Kraken`
  - `"rank wording"` — rank 1 → `(most in their last 10 games)`; rank == games → `(fewest in their last 10 games)`; games 6, rank 3 → `(3rd most in their last 6 games)`; games 2 → no parenthetical
  - `"omits the opponent line without opponent data"`
  - `"omits a split with no ice time"` — `power_play: nil` → `Even strength 39.58 · Penalty kill 2.22`
  - `"skips skaters without a name and fills from the next"` — `names` returns nil for the top skater → three lines from skaters 2–4
  - `"no skater post without skaters"` and `"no season-marks post without marks"` → `posts.size`
  - `"top of list reads without an ordinal"` — rank 1 shot → `(hardest)`; rank 1 speed → `(fastest)`
  - `"season marks drop trailing lines to fit the limit"` — `limit: 120` with three marks → post length ≤ 120 and still starts with the header
- [ ] **Step 2: Run** `mise exec -- bundle exec rails test test/services/rod_the_bot/edge_recap/formatter_test.rb` — expect `NameError`.
- [ ] **Step 3: Implement.** Use `ActiveSupport::Inflector.ordinalize` for ordinals; show at most three skaters.
- [ ] **Step 4: Run** — expect pass.
- [ ] **Step 5: Commit** `Add EDGE recap formatter`.

### Task 4: Worker and scheduler

**Files:**
- Create: `app/workers/rod_the_bot/edge_game_recap_worker.rb`
- Modify: `app/workers/rod_the_bot/scheduler.rb` (next to `YesterdaysScoresWorker.perform_in(5.minutes)`)
- Test: `test/workers/rod_the_bot/edge_game_recap_worker_test.rb`, `test/workers/rod_the_bot/scheduler_test.rb`
- Modify: `AGENTS.md` only if a new policy emerges (none expected).

**Interfaces:**
- Consumes: Task 1 client methods with `game_id:` and `fresh: true`; `GameData.build`; `Formatter#posts`; `Nhl::ScheduleClient.todays_game(date:)`; `Nhl::GameClient.boxscore(game_id)` (`homeTeam`/`awayTeam` with `id`, `commonName.default`; `playerByGameStats.<side>.forwards|defense[].playerId`); `Nhl::PlayerDirectory.for_game(game_id)`; `RodTheBot::PostThread.enqueue(chunks, key:)`.
- Produces: `RodTheBot::EdgeGameRecapWorker#perform(attempt = 0)` with `RETRY_DELAY = 30.minutes`, `MAX_ATTEMPTS = 6`, claim key `edge_recap:<game_id>:claimed` (`SET NX`, two-day TTL), thread key `edge_recap_<game_id>`. Scheduler calls `RodTheBot::EdgeGameRecapWorker.perform_in(7.minutes)` in season.

Behavior, in order:
1. Return if `Nhl::SeasonCalendar.preseason?`.
2. Yesterday = today in `TIME_ZONE` minus one day. Return unless the game exists, `gameType != 1`, `gameScheduleState == "OK"`, and `gameState` is `"OFF"` or `"FINAL"`.
3. Fetch team distance (`fresh: true`). `Nhl::RequestError` → `retry_job(e, game_id:, operation: "edge_game_recap")`.
4. Fetch opponent distance, shots, speeds, each rescuing `Nhl::RequestError` to nil with a warning; fetch each dressed tracked-team skater's distance, skipping failures.
5. `GameData.build`; nil → if `attempt < MAX_ATTEMPTS`, `perform_in(RETRY_DELAY, attempt + 1)`, else warn with the game ID. No claim is taken on this path.
6. Take the claim; return if already claimed. Enqueue the thread; on an exception delete the claim and re-raise.

- [ ] **Step 1: Write failing worker tests** (stub clients with Mocha; build payloads with the same helper shape as Task 2; freeze time with Timecop at `Time.zone.local(2026, 11, 15, 10)`):
  - `"posts a thread for yesterday's game"` — `RodTheBot::Post.jobs.size == 3`; first job's options key `edge_recap_2026020321:1`; first text starts `⛸️ EDGE recap: Hurricanes vs. Kraken`
  - `"requests fresh data for the game's season"` — expects `fetch_team_skating_distance_detail(12, game_id: 2026020321, fresh: true)`
  - `"does nothing without a game yesterday"`, `"does nothing in the preseason"`, `"does nothing when the game was not played to a final"` (`gameState: "FUT"`, and `gameScheduleState: "PPD"`) — no posts, no jobs
  - `"reschedules when EDGE has not published the game"` — one `EdgeGameRecapWorker` job with args `[1]`, no posts
  - `"gives up after the last attempt"` — `perform(6)` → no jobs, `Rails.logger.expects(:warn)` with text including `2026020321`
  - `"skips a skater whose data fails"` — one skater fetch raises `Nhl::RequestError` → thread still posts, that player absent
  - `"posts without season marks when shot speed fails"` — 2 posts
  - `"raises when team distance fails"` — `assert_raises(Nhl::RequestError)`
  - `"does not post twice for the same game"` — `perform` twice → 3 posts total
- [ ] **Step 2: Add scheduler test assertions** — in-season cases expect `RodTheBot::EdgeGameRecapWorker.jobs.size == 1`; the offseason case expects 0.
- [ ] **Step 3: Run** both test files — expect failures.
- [ ] **Step 4: Implement** the worker (include `Sidekiq::Worker`, `WorkerErrorHandling`) and the scheduler line.
- [ ] **Step 5: Run** both files — expect pass.
- [ ] **Step 6: Commit** `Post a morning EDGE recap thread after each game`.

### Task 5: Verification

- [ ] `git diff --check`
- [ ] `mise exec -- bundle exec standardrb` on changed files
- [ ] `PARALLEL_WORKERS=1 mise exec -- bundle exec rails test` — expect 0 failures, 0 errors, 2 skips (unchanged)
- [ ] `LC_ALL=en_US.UTF-8 mise exec -- ruby vendor/find_unused_vcr_cassettes.rb` — no unused cassettes
- [ ] Dry run against live data for game 2026020321 (build the posts in a console or runner without enqueuing) and compare with the spec's example.

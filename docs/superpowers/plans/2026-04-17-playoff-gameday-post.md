# Playoff Gameday Post Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update the daily gameday post so that during the NHL postseason it shows round/game/series status and seed labels instead of regular-season records.

**Architecture:** Add a third branch to the existing `if NhlApi.preseason? ... else ...` gameday-post conditional in `Scheduler#perform`. Extract two small private helpers on `Scheduler` (`playoff_status_line`, `playoff_series_state`) to format the status line. Reuse the existing `NhlApi.playoff_seed_labels` method. Fall back to the regular-season template if `seriesStatus` is absent from the game payload.

**Tech Stack:** Ruby on Rails, Sidekiq, Minitest + Mocha, Timecop (already in use).

**Spec:** `docs/superpowers/specs/2026-04-17-playoff-gameday-post-design.md`

---

## File Structure

- **Modify:** `app/workers/rod_the_bot/scheduler.rb`
  - Add `elsif` branch in the `gameday_post` conditional (around lines 54-84).
  - Add private helpers `playoff_status_line(series_status)` and `playoff_series_state(series_status)` (near the existing `record` helper around line 151).
- **Modify:** `test/workers/rod_the_bot/scheduler_test.rb`
  - Add `test_perform_postseason_gameday` — happy path with seed labels and a mid-series game.
  - Add `test_perform_postseason_gameday_series_tied` — game 1, series tied 0-0.
  - Add `test_perform_postseason_gameday_falls_back_without_series_status` — postseason but `seriesStatus` absent.
- **Delete:** `tmp/playoff_gameday_preview.rb`, `tmp/playoff_gameday_post_preview.txt` (preview artifacts from brainstorming).

---

## Task 1: Add `playoff_series_state` helper

Small pure helper that turns a `seriesStatus` hash into a string like `"Series tied 0-0"`, `"CAR leads 2-1"`, or `"OTT leads 2-1"`. Matches the wording of `YesterdaysScoresWorker#format_series_status` (already in the codebase).

**Files:**
- Modify: `app/workers/rod_the_bot/scheduler.rb` — add private method near line 151.
- Modify: `test/workers/rod_the_bot/scheduler_test.rb` — add unit tests.

- [ ] **Step 1: Write the failing tests**

Append to `test/workers/rod_the_bot/scheduler_test.rb` just before the `def teardown` line:

```ruby
  def test_playoff_series_state_tied
    series = {"topSeedWins" => 0, "bottomSeedWins" => 0, "topSeedTeamAbbrev" => "CAR", "bottomSeedTeamAbbrev" => "OTT"}
    assert_equal "Series tied 0-0", @worker.send(:playoff_series_state, series)
  end

  def test_playoff_series_state_top_seed_leads
    series = {"topSeedWins" => 2, "bottomSeedWins" => 1, "topSeedTeamAbbrev" => "CAR", "bottomSeedTeamAbbrev" => "OTT"}
    assert_equal "CAR leads 2-1", @worker.send(:playoff_series_state, series)
  end

  def test_playoff_series_state_bottom_seed_leads
    series = {"topSeedWins" => 1, "bottomSeedWins" => 2, "topSeedTeamAbbrev" => "CAR", "bottomSeedTeamAbbrev" => "OTT"}
    assert_equal "OTT leads 2-1", @worker.send(:playoff_series_state, series)
  end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rails test test/workers/rod_the_bot/scheduler_test.rb -n /playoff_series_state/
```

Expected: 3 failures/errors with `NoMethodError: private method 'playoff_series_state' ...` or similar.

- [ ] **Step 3: Add the helper**

In `app/workers/rod_the_bot/scheduler.rb`, find the `record` private method (around line 151) and add immediately above it:

```ruby
    def playoff_series_state(series_status)
      top_wins = series_status["topSeedWins"]
      bottom_wins = series_status["bottomSeedWins"]

      if top_wins == bottom_wins
        "Series tied #{top_wins}-#{bottom_wins}"
      elsif top_wins > bottom_wins
        "#{series_status["topSeedTeamAbbrev"]} leads #{top_wins}-#{bottom_wins}"
      else
        "#{series_status["bottomSeedTeamAbbrev"]} leads #{bottom_wins}-#{top_wins}"
      end
    end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rails test test/workers/rod_the_bot/scheduler_test.rb -n /playoff_series_state/
```

Expected: 3 runs, 3 assertions, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/workers/rod_the_bot/scheduler.rb test/workers/rod_the_bot/scheduler_test.rb
git commit -m "$(cat <<'EOF'
Add playoff_series_state helper to scheduler

Formats a seriesStatus payload as "Series tied N-N" or "ABBR leads N-N",
matching the wording used by YesterdaysScoresWorker.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add `playoff_status_line` helper

Combines round + game number + series state into the full status line:
`Round 1, Game 3 — CAR leads 2-1`

**Files:**
- Modify: `app/workers/rod_the_bot/scheduler.rb` — add private method.
- Modify: `test/workers/rod_the_bot/scheduler_test.rb` — add unit tests.

- [ ] **Step 1: Write the failing tests**

Append to `test/workers/rod_the_bot/scheduler_test.rb` just before `def teardown`:

```ruby
  def test_playoff_status_line_game_one
    series = {
      "round" => 1,
      "gameNumberOfSeries" => 1,
      "topSeedWins" => 0,
      "bottomSeedWins" => 0,
      "topSeedTeamAbbrev" => "CAR",
      "bottomSeedTeamAbbrev" => "OTT"
    }
    assert_equal "Round 1, Game 1 — Series tied 0-0", @worker.send(:playoff_status_line, series)
  end

  def test_playoff_status_line_mid_series
    series = {
      "round" => 2,
      "gameNumberOfSeries" => 4,
      "topSeedWins" => 2,
      "bottomSeedWins" => 1,
      "topSeedTeamAbbrev" => "CAR",
      "bottomSeedTeamAbbrev" => "OTT"
    }
    assert_equal "Round 2, Game 4 — CAR leads 2-1", @worker.send(:playoff_status_line, series)
  end
```

The em dash in the expected string is `—` (U+2014).

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rails test test/workers/rod_the_bot/scheduler_test.rb -n /playoff_status_line/
```

Expected: 2 failures/errors — `NoMethodError` or similar.

- [ ] **Step 3: Add the helper**

In `app/workers/rod_the_bot/scheduler.rb`, immediately above the `playoff_series_state` method added in Task 1, add:

```ruby
    def playoff_status_line(series_status)
      "Round #{series_status["round"]}, Game #{series_status["gameNumberOfSeries"]} — #{playoff_series_state(series_status)}"
    end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rails test test/workers/rod_the_bot/scheduler_test.rb -n /playoff_status_line/
```

Expected: 2 runs, 2 assertions, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/workers/rod_the_bot/scheduler.rb test/workers/rod_the_bot/scheduler_test.rb
git commit -m "$(cat <<'EOF'
Add playoff_status_line helper to scheduler

Builds the "Round N, Game M — {series state}" line shown at the top of
playoff gameday posts.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Add postseason branch to gameday-post builder

Add a third branch to the `gameday_post = if NhlApi.preseason? ... else ...` conditional. Guards on `@game["seriesStatus"]` so a missing field falls through to the regular-season template.

**Files:**
- Modify: `app/workers/rod_the_bot/scheduler.rb` (lines ~53-84).
- Modify: `test/workers/rod_the_bot/scheduler_test.rb`.

- [ ] **Step 1: Write the failing test (happy path, mid-series)**

Append to `test/workers/rod_the_bot/scheduler_test.rb` just before `def teardown`:

```ruby
  def test_perform_postseason_gameday
    game = {
      "id" => 2025030134,
      "gameScheduleState" => "OK",
      "startTimeUTC" => "2026-04-24T23:00:00Z",
      "venue" => {"default" => "Lenovo Center"},
      "homeTeam" => {"id" => 12, "abbrev" => "CAR", "logo" => "home.svg"},
      "awayTeam" => {"id" => 9, "abbrev" => "OTT", "logo" => "away.svg"},
      "tvBroadcasts" => [
        {"countryCode" => "US", "market" => "N", "network" => "ESPN"}
      ],
      "seriesStatus" => {
        "round" => 1,
        "gameNumberOfSeries" => 4,
        "topSeedTeamAbbrev" => "CAR",
        "topSeedWins" => 2,
        "bottomSeedTeamAbbrev" => "OTT",
        "bottomSeedWins" => 1,
        "neededToWin" => 4
      }
    }

    NhlApi.stubs(:offseason?).returns(false)
    NhlApi.stubs(:preseason?).returns(false)
    NhlApi.stubs(:postseason?).returns(true)
    NhlApi.stubs(:todays_game).returns(game)
    NhlApi.stubs(:team_standings).with("CAR").returns({team_name: "Carolina Hurricanes"})
    NhlApi.stubs(:team_standings).with("OTT").returns({team_name: "Ottawa Senators"})
    NhlApi.stubs(:playoff_seed_labels).returns({"CAR" => "M1", "OTT" => "WC2"})

    Timecop.freeze(Date.new(2026, 4, 24)) do
      @worker.perform
    end

    expected_output = <<~POST
      🗣️ It's a Carolina Hurricanes Playoff Gameday!
      
      Round 1, Game 4 — CAR leads 2-1
      
      (WC2) Ottawa Senators
      
      at 
      
      (M1) Carolina Hurricanes
      
      ⏰ 7:00 PM EDT
      📍 Lenovo Center
      📺 ESPN
    POST

    assert_equal 1, RodTheBot::Post.jobs.size
    assert_equal expected_output, RodTheBot::Post.jobs.first["args"].first
  end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bundle exec rails test test/workers/rod_the_bot/scheduler_test.rb -n test_perform_postseason_gameday
```

Expected: FAIL — output will be the regular-season template with records, not the playoff template.

- [ ] **Step 3: Update the gameday-post conditional**

In `app/workers/rod_the_bot/scheduler.rb`, locate the block starting at line 53:

```ruby
      if away["id"].to_i == ENV["NHL_TEAM_ID"].to_i || home["id"].to_i == ENV["NHL_TEAM_ID"].to_i
        gameday_post = if NhlApi.preseason?
          <<~POST
            🗣️ It's a #{your_standings[:team_name]} Preseason Gameday!

            #{away_standings[:team_name]}

            at 

            #{home_standings[:team_name]}
            
            ⏰ #{time_string}
            📍 #{venue["default"]}
            📺 #{tv}
          POST
        else
          <<~POST
            🗣️ It's a #{your_standings[:team_name]} Gameday!

            #{away_standings[:team_name]}
            #{record(away_standings)}

            at 

            #{home_standings[:team_name]}
            #{record(home_standings)}
            
            ⏰ #{time_string}
            📍 #{venue["default"]}
            📺 #{tv}
          POST
        end
```

Replace with:

```ruby
      if away["id"].to_i == ENV["NHL_TEAM_ID"].to_i || home["id"].to_i == ENV["NHL_TEAM_ID"].to_i
        gameday_post = if NhlApi.preseason?
          <<~POST
            🗣️ It's a #{your_standings[:team_name]} Preseason Gameday!

            #{away_standings[:team_name]}

            at 

            #{home_standings[:team_name]}
            
            ⏰ #{time_string}
            📍 #{venue["default"]}
            📺 #{tv}
          POST
        elsif NhlApi.postseason? && @game["seriesStatus"]
          seed_labels = NhlApi.playoff_seed_labels
          away_seed = seed_labels[away["abbrev"]] ? "(#{seed_labels[away["abbrev"]]}) " : ""
          home_seed = seed_labels[home["abbrev"]] ? "(#{seed_labels[home["abbrev"]]}) " : ""
          <<~POST
            🗣️ It's a #{your_standings[:team_name]} Playoff Gameday!

            #{playoff_status_line(@game["seriesStatus"])}

            #{away_seed}#{away_standings[:team_name]}

            at 

            #{home_seed}#{home_standings[:team_name]}
            
            ⏰ #{time_string}
            📍 #{venue["default"]}
            📺 #{tv}
          POST
        else
          <<~POST
            🗣️ It's a #{your_standings[:team_name]} Gameday!

            #{away_standings[:team_name]}
            #{record(away_standings)}

            at 

            #{home_standings[:team_name]}
            #{record(home_standings)}
            
            ⏰ #{time_string}
            📍 #{venue["default"]}
            📺 #{tv}
          POST
        end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bundle exec rails test test/workers/rod_the_bot/scheduler_test.rb -n test_perform_postseason_gameday
```

Expected: 1 run, 2 assertions, 0 failures.

- [ ] **Step 5: Add test for Game 1 / series tied**

Append to `test/workers/rod_the_bot/scheduler_test.rb` just before `def teardown`:

```ruby
  def test_perform_postseason_gameday_series_tied
    game = {
      "id" => 2025030131,
      "gameScheduleState" => "OK",
      "startTimeUTC" => "2026-04-18T19:00:00Z",
      "venue" => {"default" => "Lenovo Center"},
      "homeTeam" => {"id" => 12, "abbrev" => "CAR", "logo" => "home.svg"},
      "awayTeam" => {"id" => 9, "abbrev" => "OTT", "logo" => "away.svg"},
      "tvBroadcasts" => [
        {"countryCode" => "US", "market" => "N", "network" => "ESPN"}
      ],
      "seriesStatus" => {
        "round" => 1,
        "gameNumberOfSeries" => 1,
        "topSeedTeamAbbrev" => "CAR",
        "topSeedWins" => 0,
        "bottomSeedTeamAbbrev" => "OTT",
        "bottomSeedWins" => 0,
        "neededToWin" => 4
      }
    }

    NhlApi.stubs(:offseason?).returns(false)
    NhlApi.stubs(:preseason?).returns(false)
    NhlApi.stubs(:postseason?).returns(true)
    NhlApi.stubs(:todays_game).returns(game)
    NhlApi.stubs(:team_standings).with("CAR").returns({team_name: "Carolina Hurricanes"})
    NhlApi.stubs(:team_standings).with("OTT").returns({team_name: "Ottawa Senators"})
    NhlApi.stubs(:playoff_seed_labels).returns({"CAR" => "M1", "OTT" => "WC2"})

    Timecop.freeze(Date.new(2026, 4, 18)) do
      @worker.perform
    end

    post = RodTheBot::Post.jobs.first["args"].first
    assert_includes post, "🗣️ It's a Carolina Hurricanes Playoff Gameday!"
    assert_includes post, "Round 1, Game 1 — Series tied 0-0"
    assert_includes post, "(WC2) Ottawa Senators"
    assert_includes post, "(M1) Carolina Hurricanes"
  end
```

- [ ] **Step 6: Run test**

```bash
bundle exec rails test test/workers/rod_the_bot/scheduler_test.rb -n test_perform_postseason_gameday_series_tied
```

Expected: 1 run, 4 assertions, 0 failures.

- [ ] **Step 7: Add fallback test when seed labels missing**

Append to `test/workers/rod_the_bot/scheduler_test.rb` just before `def teardown`:

```ruby
  def test_perform_postseason_gameday_without_seed_labels
    game = {
      "id" => 2025030131,
      "gameScheduleState" => "OK",
      "startTimeUTC" => "2026-04-18T19:00:00Z",
      "venue" => {"default" => "Lenovo Center"},
      "homeTeam" => {"id" => 12, "abbrev" => "CAR", "logo" => "home.svg"},
      "awayTeam" => {"id" => 9, "abbrev" => "OTT", "logo" => "away.svg"},
      "tvBroadcasts" => [
        {"countryCode" => "US", "market" => "N", "network" => "ESPN"}
      ],
      "seriesStatus" => {
        "round" => 1,
        "gameNumberOfSeries" => 1,
        "topSeedTeamAbbrev" => "CAR",
        "topSeedWins" => 0,
        "bottomSeedTeamAbbrev" => "OTT",
        "bottomSeedWins" => 0,
        "neededToWin" => 4
      }
    }

    NhlApi.stubs(:offseason?).returns(false)
    NhlApi.stubs(:preseason?).returns(false)
    NhlApi.stubs(:postseason?).returns(true)
    NhlApi.stubs(:todays_game).returns(game)
    NhlApi.stubs(:team_standings).with("CAR").returns({team_name: "Carolina Hurricanes"})
    NhlApi.stubs(:team_standings).with("OTT").returns({team_name: "Ottawa Senators"})
    NhlApi.stubs(:playoff_seed_labels).returns({})

    Timecop.freeze(Date.new(2026, 4, 18)) do
      @worker.perform
    end

    post = RodTheBot::Post.jobs.first["args"].first
    assert_includes post, "Playoff Gameday!"
    assert_includes post, "Ottawa Senators"
    assert_includes post, "Carolina Hurricanes"
    refute_includes post, "()"
    refute_includes post, "(WC"
    refute_includes post, "(M"
  end
```

- [ ] **Step 8: Run test**

```bash
bundle exec rails test test/workers/rod_the_bot/scheduler_test.rb -n test_perform_postseason_gameday_without_seed_labels
```

Expected: 1 run, 6 assertions, 0 failures.

- [ ] **Step 9: Add fallback test when seriesStatus missing**

Append to `test/workers/rod_the_bot/scheduler_test.rb` just before `def teardown`:

```ruby
  def test_perform_postseason_gameday_falls_back_without_series_status
    game = {
      "id" => 2025030131,
      "gameScheduleState" => "OK",
      "startTimeUTC" => "2026-04-18T19:00:00Z",
      "venue" => {"default" => "Lenovo Center"},
      "homeTeam" => {"id" => 12, "abbrev" => "CAR", "logo" => "home.svg"},
      "awayTeam" => {"id" => 9, "abbrev" => "OTT", "logo" => "away.svg"},
      "tvBroadcasts" => [
        {"countryCode" => "US", "market" => "N", "network" => "ESPN"}
      ]
      # seriesStatus intentionally absent
    }

    NhlApi.stubs(:offseason?).returns(false)
    NhlApi.stubs(:preseason?).returns(false)
    NhlApi.stubs(:postseason?).returns(true)
    NhlApi.stubs(:todays_game).returns(game)
    NhlApi.stubs(:team_standings).with("CAR").returns({
      team_name: "Carolina Hurricanes", wins: 40, losses: 20, ot: 5,
      points: 85, division_rank: 1, division_name: "Metropolitan"
    })
    NhlApi.stubs(:team_standings).with("OTT").returns({
      team_name: "Ottawa Senators", wins: 38, losses: 25, ot: 4,
      points: 80, division_rank: 5, division_name: "Atlantic"
    })

    Timecop.freeze(Date.new(2026, 4, 18)) do
      @worker.perform
    end

    post = RodTheBot::Post.jobs.first["args"].first
    refute_includes post, "Playoff Gameday"
    assert_includes post, "🗣️ It's a Carolina Hurricanes Gameday!"
    assert_includes post, "(40-20-5, 85 points)"
  end
```

- [ ] **Step 10: Run test**

```bash
bundle exec rails test test/workers/rod_the_bot/scheduler_test.rb -n test_perform_postseason_gameday_falls_back_without_series_status
```

Expected: 1 run, 3 assertions, 0 failures.

- [ ] **Step 11: Run the full scheduler test suite to verify no regressions**

```bash
bundle exec rails test test/workers/rod_the_bot/scheduler_test.rb
```

Expected: all tests pass (original 3 + 5 new playoff tests + 2 earlier helper tests from Tasks 1-2 = 10 runs).

- [ ] **Step 12: Commit**

```bash
git add app/workers/rod_the_bot/scheduler.rb test/workers/rod_the_bot/scheduler_test.rb
git commit -m "$(cat <<'EOF'
Render playoff gameday posts with series context

Add a postseason branch to the Scheduler gameday-post template that
shows round, game number, series state, and seed labels instead of
regular-season records. Falls back to the regular-season template if
seriesStatus is missing from the game payload.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Remove preview artifacts

The `tmp/playoff_gameday_preview.rb` script and its output file were brainstorming artifacts — no longer needed.

**Files:**
- Delete: `tmp/playoff_gameday_preview.rb`
- Delete: `tmp/playoff_gameday_post_preview.txt`
- Delete: `tmp/playoff_post_preview.txt` (earlier postseason-series preview from same thread)

- [ ] **Step 1: Verify files are untracked**

```bash
git ls-files tmp/playoff_gameday_preview.rb tmp/playoff_gameday_post_preview.txt tmp/playoff_post_preview.txt
```

Expected: no output (files are not tracked by git). If any path shows up, use `git rm` instead of `rm` for that file.

- [ ] **Step 2: Remove files**

```bash
rm tmp/playoff_gameday_preview.rb tmp/playoff_gameday_post_preview.txt tmp/playoff_post_preview.txt
```

- [ ] **Step 3: No commit needed**

These files are in `tmp/` which is gitignored. No commit required.

---

## Final Verification

- [ ] Run the full test suite to verify no regressions anywhere in the repo:

```bash
bundle exec rails test
```

Expected: all tests pass.

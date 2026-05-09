# End-of-Period Shot Chart Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** At the end of each regulation period and overtime, post an MP4 shot-chart animation to the game thread that shows cumulative shots, with the just-completed period's shots animating in chronologically.

**Architecture:** A `RodTheBot::ShotChartAnimator` service pulls play-by-play data, normalizes coordinates so the home team always attacks right, then composites shot markers over a programmatically-rendered NHL rink using MiniMagick. Per-frame PNGs are stitched into an MP4 with ffmpeg. A new `RodTheBot::EndOfPeriodShotChartWorker` invokes the service and posts the result via the existing `RodTheBot::Post` worker. One line is added to `EndOfPeriodWorker` to enqueue it.

**Tech Stack:** Ruby/Rails, Sidekiq, `mini_magick` (already in Gemfile), `streamio-ffmpeg` (already in Gemfile), `ffmpeg`/`imagemagick` system binaries (already in Dockerfile). Tests use Minitest + VCR + Mocha + `Sidekiq::Testing.fake!` (project default — see `test/test_helper.rb`).

## Spec deviation

The design spec calls the rink a checked-in static PNG asset. This plan instead uses a small Ruby renderer module that produces the rink as a MiniMagick image at runtime, memoized per render. Rationale: keeps the rink design as code (easy to tweak, no binary churn in git) without measurably affecting render time. The user's design intent — a single hand-tuned rink image reused per frame — is preserved.

## File map

- Create `app/services/rod_the_bot/shot_chart_animator/coord_normalizer.rb` — pure functions for coord flipping and canvas mapping.
- Create `app/services/rod_the_bot/shot_chart_animator/shot_extractor.rb` — extracts plottable shots from a PBP feed.
- Create `app/services/rod_the_bot/shot_chart_animator/rink_renderer.rb` — produces the base rink MiniMagick image.
- Create `app/services/rod_the_bot/shot_chart_animator/frame_compositor.rb` — composes one frame on top of the rink.
- Create `app/services/rod_the_bot/shot_chart_animator.rb` — orchestrator: PBP → frames → MP4.
- Create `app/workers/rod_the_bot/end_of_period_shot_chart_worker.rb` — Sidekiq worker.
- Modify `app/workers/rod_the_bot/end_of_period_worker.rb` — one-line enqueue.
- Create `test/services/rod_the_bot/shot_chart_animator/coord_normalizer_test.rb`
- Create `test/services/rod_the_bot/shot_chart_animator/shot_extractor_test.rb`
- Create `test/services/rod_the_bot/shot_chart_animator/rink_renderer_test.rb`
- Create `test/services/rod_the_bot/shot_chart_animator/frame_compositor_test.rb`
- Create `test/services/rod_the_bot/shot_chart_animator_test.rb`
- Create `test/workers/end_of_period_shot_chart_worker_test.rb`
- Modify `test/workers/end_of_period_worker_test.rb` — assert new enqueue.
- Reuse VCR fixture `fixtures/vcr_cassettes/nhl_game_2024020477_gamecenter_pbp_end_of_period_1.yml` (already exists).
- Create `test/fixtures/files/test_shot_chart.mp4` — 1-byte placeholder for `Rails.env.test?` short-circuit.

## Constants

Place in `RodTheBot::ShotChartAnimator` (or a CONSTANTS module inside it):

```ruby
CANVAS_WIDTH    = 1200
CANVAS_HEIGHT   = 510
NHL_X_RANGE     = 200.0  # -100..+100 feet
NHL_Y_RANGE     = 85.0   # -42.5..+42.5 feet
SHOT_RADIUS     = 7      # px (diameter ~14)
GOAL_RADIUS     = 11     # px (diameter ~22)
FRAME_FPS       = 30
INTRO_SECONDS   = 1.0
OUTRO_SECONDS   = 3.0
POP_SECONDS     = 0.3
TOTAL_BUDGET    = 50.0
MAX_VIDEO_BYTES = 50 * 1024 * 1024
MAX_VIDEO_SECS  = 60
```

Team color map (small constant — implementer can expand later if needed):

```ruby
TEAM_COLORS = {
  "ANA" => "#F47A38", "ARI" => "#8C2633", "BOS" => "#FFB81C", "BUF" => "#003087",
  "CGY" => "#D2001C", "CAR" => "#CC0000", "CHI" => "#CF0A2C", "COL" => "#6F263D",
  "CBJ" => "#002654", "DAL" => "#006847", "DET" => "#CE1126", "EDM" => "#FF4C00",
  "FLA" => "#C8102E", "LAK" => "#000000", "MIN" => "#154734", "MTL" => "#AF1E2D",
  "NSH" => "#FFB81C", "NJD" => "#CE1126", "NYI" => "#00539B", "NYR" => "#0038A8",
  "OTT" => "#C8102E", "PHI" => "#F74902", "PIT" => "#FCB514", "SJS" => "#006D75",
  "SEA" => "#001628", "STL" => "#002F87", "TBL" => "#002868", "TOR" => "#00205B",
  "UTA" => "#71AFE5", "VAN" => "#00205B", "VGK" => "#B4975A", "WSH" => "#C8102E",
  "WPG" => "#041E42"
}.freeze
```

---

## Task 1: Coordinate normalizer

**Files:**
- Create: `app/services/rod_the_bot/shot_chart_animator/coord_normalizer.rb`
- Test: `test/services/rod_the_bot/shot_chart_animator/coord_normalizer_test.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/services/rod_the_bot/shot_chart_animator/coord_normalizer_test.rb`:

```ruby
require "test_helper"

class RodTheBot::ShotChartAnimator::CoordNormalizerTest < ActiveSupport::TestCase
  CN = RodTheBot::ShotChartAnimator::CoordNormalizer

  def test_normalize_does_not_flip_when_home_attacks_right
    nx, ny = CN.normalize(x: 50, y: 10, home_defending_side: "left")
    assert_equal 50, nx
    assert_equal 10, ny
  end

  def test_normalize_flips_when_home_defends_right
    nx, ny = CN.normalize(x: 50, y: 10, home_defending_side: "right")
    assert_equal(-50, nx)
    assert_equal(-10, ny)
  end

  def test_to_canvas_maps_center_ice_to_canvas_center
    cx, cy = CN.to_canvas(0, 0)
    assert_in_delta 600.0, cx, 0.001
    assert_in_delta 255.0, cy, 0.001
  end

  def test_to_canvas_maps_offensive_corner
    cx, cy = CN.to_canvas(100, 42.5)
    assert_in_delta 1200.0, cx, 0.001
    assert_in_delta 510.0, cy, 0.001
  end

  def test_to_canvas_maps_defensive_corner
    cx, cy = CN.to_canvas(-100, -42.5)
    assert_in_delta 0.0, cx, 0.001
    assert_in_delta 0.0, cy, 0.001
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/rod_the_bot/shot_chart_animator/coord_normalizer_test.rb`
Expected: All fail with `NameError: uninitialized constant RodTheBot::ShotChartAnimator::CoordNormalizer`.

- [ ] **Step 3: Implement the module**

Create `app/services/rod_the_bot/shot_chart_animator/coord_normalizer.rb`:

```ruby
module RodTheBot
  class ShotChartAnimator
    module CoordNormalizer
      CANVAS_WIDTH  = 1200
      CANVAS_HEIGHT = 510
      NHL_X_RANGE   = 200.0
      NHL_Y_RANGE   = 85.0

      module_function

      # Canonical orientation: home team always attacks right.
      # Flip both coords for periods where home defends right (i.e., attacks left).
      def normalize(x:, y:, home_defending_side:)
        if home_defending_side == "right"
          [-x, -y]
        else
          [x, y]
        end
      end

      def to_canvas(nhl_x, nhl_y)
        cx = (nhl_x + 100.0) / NHL_X_RANGE * CANVAS_WIDTH
        cy = (nhl_y + 42.5)  / NHL_Y_RANGE * CANVAS_HEIGHT
        [cx, cy]
      end
    end
  end
end
```

(The outer `RodTheBot::ShotChartAnimator` class will be created in Task 7. Until then this file just defines a module under a not-yet-existing class scope. Define a minimal stub at the top of this file to avoid load errors:)

```ruby
module RodTheBot
  class ShotChartAnimator
  end
end
```

…then place the `CoordNormalizer` module inside that. Replace the stub class body in Task 7 — keep the `class ShotChartAnimator` re-open pattern Ruby allows.

Final file contents:

```ruby
module RodTheBot
  class ShotChartAnimator
  end

  class ShotChartAnimator
    module CoordNormalizer
      CANVAS_WIDTH  = 1200
      CANVAS_HEIGHT = 510
      NHL_X_RANGE   = 200.0
      NHL_Y_RANGE   = 85.0

      module_function

      def normalize(x:, y:, home_defending_side:)
        if home_defending_side == "right"
          [-x, -y]
        else
          [x, y]
        end
      end

      def to_canvas(nhl_x, nhl_y)
        cx = (nhl_x + 100.0) / NHL_X_RANGE * CANVAS_WIDTH
        cy = (nhl_y + 42.5)  / NHL_Y_RANGE * CANVAS_HEIGHT
        [cx, cy]
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/rod_the_bot/shot_chart_animator/coord_normalizer_test.rb`
Expected: 5 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/rod_the_bot/shot_chart_animator/coord_normalizer.rb \
        test/services/rod_the_bot/shot_chart_animator/coord_normalizer_test.rb
git commit -m "feat: add shot chart coordinate normalizer"
```

---

## Task 2: Shot extractor

**Files:**
- Create: `app/services/rod_the_bot/shot_chart_animator/shot_extractor.rb`
- Test: `test/services/rod_the_bot/shot_chart_animator/shot_extractor_test.rb`
- Reuse: `fixtures/vcr_cassettes/nhl_game_2024020477_gamecenter_pbp_end_of_period_1.yml`

- [ ] **Step 1: Write the failing tests**

Create `test/services/rod_the_bot/shot_chart_animator/shot_extractor_test.rb`:

```ruby
require "test_helper"

class RodTheBot::ShotChartAnimator::ShotExtractorTest < ActiveSupport::TestCase
  SE = RodTheBot::ShotChartAnimator::ShotExtractor

  def test_extracts_only_shots_on_goal_and_goals_through_period
    feed = VCR.use_cassette("nhl_game_2024020477_gamecenter_pbp_end_of_period_1") do
      HTTParty.get("https://api-web.nhle.com/v1/gamecenter/2024020477/play-by-play")
    end

    shots = SE.call(feed: feed, through_period: 1)

    refute_empty shots
    assert(shots.all? { |s| %w[shot-on-goal goal].include?(s[:type]) },
           "extractor should keep only SOG and goals")
    assert(shots.all? { |s| s[:period] <= 1 },
           "should not include shots from later periods")
  end

  def test_drops_shots_with_missing_coordinates
    feed = {
      "homeTeam" => {"id" => 1, "abbrev" => "HME"},
      "awayTeam" => {"id" => 2, "abbrev" => "AWY"},
      "plays" => [
        {"typeDescKey" => "shot-on-goal",
         "periodDescriptor" => {"number" => 1},
         "timeInPeriod" => "01:00",
         "homeTeamDefendingSide" => "left",
         "details" => {"xCoord" => 10, "yCoord" => 5, "eventOwnerTeamId" => 1}},
        {"typeDescKey" => "shot-on-goal",
         "periodDescriptor" => {"number" => 1},
         "timeInPeriod" => "01:30",
         "homeTeamDefendingSide" => "left",
         "details" => {"eventOwnerTeamId" => 2}} # missing coords
      ]
    }

    shots = SE.call(feed: feed, through_period: 1)
    assert_equal 1, shots.size
  end

  def test_normalizes_coords_for_period_where_home_defends_right
    feed = {
      "homeTeam" => {"id" => 1, "abbrev" => "HME"},
      "awayTeam" => {"id" => 2, "abbrev" => "AWY"},
      "plays" => [
        {"typeDescKey" => "shot-on-goal",
         "periodDescriptor" => {"number" => 2},
         "timeInPeriod" => "10:00",
         "homeTeamDefendingSide" => "right",
         "details" => {"xCoord" => 50, "yCoord" => 10, "eventOwnerTeamId" => 1}}
      ]
    }

    shots = SE.call(feed: feed, through_period: 2)
    assert_equal(-50, shots.first[:x])
    assert_equal(-10, shots.first[:y])
  end

  def test_sorts_chronologically_by_period_then_time
    feed = {
      "homeTeam" => {"id" => 1, "abbrev" => "HME"},
      "awayTeam" => {"id" => 2, "abbrev" => "AWY"},
      "plays" => [
        {"typeDescKey" => "shot-on-goal", "periodDescriptor" => {"number" => 2},
         "timeInPeriod" => "01:00", "homeTeamDefendingSide" => "left",
         "details" => {"xCoord" => 1, "yCoord" => 1, "eventOwnerTeamId" => 1}},
        {"typeDescKey" => "shot-on-goal", "periodDescriptor" => {"number" => 1},
         "timeInPeriod" => "19:00", "homeTeamDefendingSide" => "left",
         "details" => {"xCoord" => 2, "yCoord" => 2, "eventOwnerTeamId" => 2}},
        {"typeDescKey" => "shot-on-goal", "periodDescriptor" => {"number" => 1},
         "timeInPeriod" => "02:00", "homeTeamDefendingSide" => "left",
         "details" => {"xCoord" => 3, "yCoord" => 3, "eventOwnerTeamId" => 1}}
      ]
    }

    shots = SE.call(feed: feed, through_period: 2)
    assert_equal [[1, "02:00"], [1, "19:00"], [2, "01:00"]],
                 shots.map { |s| [s[:period], s[:time_in_period]] }
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/rod_the_bot/shot_chart_animator/shot_extractor_test.rb`
Expected: All 4 fail with `NameError: uninitialized constant RodTheBot::ShotChartAnimator::ShotExtractor`.

- [ ] **Step 3: Implement the module**

Create `app/services/rod_the_bot/shot_chart_animator/shot_extractor.rb`:

```ruby
module RodTheBot
  class ShotChartAnimator
    module ShotExtractor
      PLOTTABLE_TYPES = %w[shot-on-goal goal].freeze

      module_function

      def call(feed:, through_period:)
        plays = Array(feed["plays"])
        home_id = feed.dig("homeTeam", "id")
        away_id = feed.dig("awayTeam", "id")

        shots = plays.filter_map do |play|
          next unless PLOTTABLE_TYPES.include?(play["typeDescKey"])

          period = play.dig("periodDescriptor", "number").to_i
          next if period <= 0 || period > through_period

          details = play["details"] || {}
          x = details["xCoord"]
          y = details["yCoord"]
          next if x.nil? || y.nil?

          nx, ny = CoordNormalizer.normalize(
            x: x, y: y,
            home_defending_side: play["homeTeamDefendingSide"]
          )

          team_id = details["eventOwnerTeamId"]
          team_side = if team_id == home_id then :home
                      elsif team_id == away_id then :away
                      else :unknown
                      end

          {
            event_id: play["eventId"],
            period: period,
            time_in_period: play["timeInPeriod"],
            type: play["typeDescKey"],
            x: nx,
            y: ny,
            team_id: team_id,
            team_side: team_side,
            away_score: details["awayScore"],
            home_score: details["homeScore"]
          }
        end

        shots.sort_by { |s| [s[:period], s[:time_in_period].to_s] }
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/rod_the_bot/shot_chart_animator/shot_extractor_test.rb`
Expected: 4 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/rod_the_bot/shot_chart_animator/shot_extractor.rb \
        test/services/rod_the_bot/shot_chart_animator/shot_extractor_test.rb
git commit -m "feat: add shot extractor with coord normalization"
```

---

## Task 3: Rink renderer

**Files:**
- Create: `app/services/rod_the_bot/shot_chart_animator/rink_renderer.rb`
- Test: `test/services/rod_the_bot/shot_chart_animator/rink_renderer_test.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/services/rod_the_bot/shot_chart_animator/rink_renderer_test.rb`:

```ruby
require "test_helper"

class RodTheBot::ShotChartAnimator::RinkRendererTest < ActiveSupport::TestCase
  def test_call_returns_path_to_canvas_sized_png
    Dir.mktmpdir do |tmp|
      out = File.join(tmp, "rink.png")
      RodTheBot::ShotChartAnimator::RinkRenderer.call(out)
      assert File.exist?(out), "rink png should be written"
      img = MiniMagick::Image.open(out)
      assert_equal 1200, img.width
      assert_equal 510, img.height
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/rod_the_bot/shot_chart_animator/rink_renderer_test.rb`
Expected: Fail with `NameError: uninitialized constant RodTheBot::ShotChartAnimator::RinkRenderer`.

- [ ] **Step 3: Implement the renderer**

Create `app/services/rod_the_bot/shot_chart_animator/rink_renderer.rb`:

```ruby
require "mini_magick"

module RodTheBot
  class ShotChartAnimator
    module RinkRenderer
      W = CoordNormalizer::CANVAS_WIDTH
      H = CoordNormalizer::CANVAS_HEIGHT

      ICE_COLOR     = "#F4F8FB"
      GOAL_LINE     = "#C8102E"
      BLUE_LINE     = "#0033A0"
      CENTER_RED    = "#C8102E"
      FACEOFF_BLUE  = "#0033A0"

      module_function

      def call(out_path)
        # Build a single MiniMagick command that paints the rink.
        MiniMagick::Tool::Convert.new do |c|
          c.size("#{W}x#{H}")
          c.canvas(ICE_COLOR)
          c.fill("transparent")
          c.stroke(GOAL_LINE)
          c.strokewidth(2)
          # Goal lines (~11ft from each end → x = ±89 → canvas x = 66 and 1134)
          c.draw "line 66,0 66,#{H}"
          c.draw "line 1134,0 1134,#{H}"
          c.stroke(BLUE_LINE)
          c.strokewidth(4)
          # Blue lines (±25ft → canvas x = 450 and 750)
          c.draw "line 450,0 450,#{H}"
          c.draw "line 750,0 750,#{H}"
          c.stroke(CENTER_RED)
          c.strokewidth(2)
          c.draw "line 600,0 600,#{H}"
          # Center circle (15ft radius → 90px)
          c.fill("transparent")
          c.stroke(FACEOFF_BLUE)
          c.strokewidth(2)
          c.draw "circle 600,255 600,165"
          # Faceoff dots/circles in each end (NHL: 20ft from goal line, 22ft from boards)
          # Dot at canvas: x = 132 / 1068, y = 123 / 387
          [[132, 123], [132, 387], [1068, 123], [1068, 387]].each do |dx, dy|
            c.fill(CENTER_RED)
            c.stroke("transparent")
            c.draw "circle #{dx},#{dy} #{dx + 4},#{dy}"
            c.fill("transparent")
            c.stroke(FACEOFF_BLUE)
            c.draw "circle #{dx},#{dy} #{dx + 90},#{dy}"
          end
          # Goal creases (~6ft semicircle in front of each goal line)
          c.fill("#A0CFEC")
          c.stroke(FACEOFF_BLUE)
          c.strokewidth(1)
          c.draw "circle 66,255 66,219"
          c.draw "circle 1134,255 1134,219"
          c.out(out_path)
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/rod_the_bot/shot_chart_animator/rink_renderer_test.rb`
Expected: 1 test, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/rod_the_bot/shot_chart_animator/rink_renderer.rb \
        test/services/rod_the_bot/shot_chart_animator/rink_renderer_test.rb
git commit -m "feat: add programmatic NHL rink renderer"
```

---

## Task 4: Frame compositor

**Files:**
- Create: `app/services/rod_the_bot/shot_chart_animator/frame_compositor.rb`
- Test: `test/services/rod_the_bot/shot_chart_animator/frame_compositor_test.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/services/rod_the_bot/shot_chart_animator/frame_compositor_test.rb`:

```ruby
require "test_helper"

class RodTheBot::ShotChartAnimator::FrameCompositorTest < ActiveSupport::TestCase
  def setup
    @rink = Tempfile.new(["rink", ".png"])
    RodTheBot::ShotChartAnimator::RinkRenderer.call(@rink.path)
  end

  def teardown
    @rink&.close!
  end

  def test_compose_writes_png_with_canvas_dimensions
    Dir.mktmpdir do |tmp|
      out = File.join(tmp, "frame.png")
      shots = [
        {x: 50, y: 0, type: "shot-on-goal", team_side: :home, period: 1, time_in_period: "10:00"},
        {x: -50, y: 5, type: "goal", team_side: :away, period: 1, time_in_period: "11:30",
         goal_number: 1}
      ]
      RodTheBot::ShotChartAnimator::FrameCompositor.compose(
        rink_path: @rink.path,
        out_path: out,
        prior_shots: [shots.first],
        new_shots: [shots.last],
        new_shot_scale: 1.0,
        active_caption: nil,
        away_abbrev: "AWY",
        home_abbrev: "HME",
        away_color: "#000000",
        home_color: "#FFFFFF",
        period_label: "End of 1st",
        away_sog: 1, home_sog: 1
      )

      assert File.exist?(out)
      img = MiniMagick::Image.open(out)
      assert_equal 1200, img.width
      assert_equal 510, img.height
    end
  end

  def test_compose_handles_zero_shots
    Dir.mktmpdir do |tmp|
      out = File.join(tmp, "frame.png")
      RodTheBot::ShotChartAnimator::FrameCompositor.compose(
        rink_path: @rink.path,
        out_path: out,
        prior_shots: [],
        new_shots: [],
        new_shot_scale: 1.0,
        active_caption: nil,
        away_abbrev: "AWY",
        home_abbrev: "HME",
        away_color: "#000000",
        home_color: "#FFFFFF",
        period_label: "End of 1st",
        away_sog: 0, home_sog: 0
      )
      assert File.exist?(out)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/rod_the_bot/shot_chart_animator/frame_compositor_test.rb`
Expected: Fail with `NameError: uninitialized constant RodTheBot::ShotChartAnimator::FrameCompositor`.

- [ ] **Step 3: Implement the compositor**

Create `app/services/rod_the_bot/shot_chart_animator/frame_compositor.rb`:

```ruby
require "mini_magick"

module RodTheBot
  class ShotChartAnimator
    module FrameCompositor
      module_function

      SHOT_RADIUS = 7
      GOAL_RADIUS = 11

      # Composites one animation frame:
      #   - prior shots (from earlier periods) drawn at 70% opacity
      #   - new shots (current period, already revealed) drawn at 100%
      #   - the most-recent new shot may have new_shot_scale applied (pop)
      #   - optional active_caption (timestamp near most-recent shot)
      def compose(rink_path:, out_path:, prior_shots:, new_shots:,
                  new_shot_scale:, active_caption:,
                  away_abbrev:, home_abbrev:, away_color:, home_color:,
                  period_label:, away_sog:, home_sog:)
        MiniMagick::Tool::Convert.new do |c|
          c << rink_path

          # Prior-period shots (70% opacity)
          prior_shots.each do |shot|
            draw_shot(c, shot, scale: 1.0, opacity: 0.7,
                      home_color: home_color, away_color: away_color)
          end

          # New-period shots (100% opacity); last one gets the pop scale
          new_shots.each_with_index do |shot, i|
            scale = (i == new_shots.length - 1) ? new_shot_scale : 1.0
            draw_shot(c, shot, scale: scale, opacity: 1.0,
                      home_color: home_color, away_color: away_color)
          end

          # Active caption near the most-recent shot
          if active_caption && new_shots.any?
            last = new_shots.last
            cx, cy = CoordNormalizer.to_canvas(last[:x], last[:y])
            c.fill("#000000")
            c.stroke("transparent")
            c.pointsize(18)
            c.draw "text #{cx.to_i + 12},#{cy.to_i - 12} '#{active_caption}'"
          end

          # Period label (bottom-center)
          c.fill("#000000")
          c.stroke("transparent")
          c.pointsize(28)
          c.gravity("South")
          c.draw "text 0,12 '#{period_label}'"

          # SOG legend (bottom-left)
          c.gravity("SouthWest")
          c.pointsize(20)
          c.draw "text 16,12 '#{away_abbrev} #{away_sog} - #{home_abbrev} #{home_sog}'"
          c.gravity("None")

          c.out(out_path)
        end
      end

      def draw_shot(c, shot, scale:, opacity:, home_color:, away_color:)
        cx, cy = CoordNormalizer.to_canvas(shot[:x], shot[:y])
        color = (shot[:team_side] == :home) ? home_color : away_color
        radius = (shot[:type] == "goal" ? GOAL_RADIUS : SHOT_RADIUS) * scale

        c.fill("#{color}#{opacity_hex(opacity)}")
        c.stroke(shot[:type] == "goal" ? "white" : "transparent")
        c.strokewidth(shot[:type] == "goal" ? 2 : 0)
        c.draw "circle #{cx.to_i},#{cy.to_i} #{(cx + radius).to_i},#{cy.to_i}"

        if shot[:type] == "goal" && shot[:goal_number]
          c.fill("white")
          c.stroke("transparent")
          c.pointsize(14)
          c.draw "text #{cx.to_i - 4},#{cy.to_i + 5} '#{shot[:goal_number]}'"
        end
      end

      def opacity_hex(opacity)
        # ImageMagick honors a trailing alpha hex pair, e.g. "#FF000080" = 50%.
        format("%02X", (opacity * 255).round.clamp(0, 255))
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/rod_the_bot/shot_chart_animator/frame_compositor_test.rb`
Expected: 2 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/rod_the_bot/shot_chart_animator/frame_compositor.rb \
        test/services/rod_the_bot/shot_chart_animator/frame_compositor_test.rb
git commit -m "feat: add per-frame shot chart compositor"
```

---

## Task 5: ShotChartAnimator orchestrator

**Files:**
- Create/Replace: `app/services/rod_the_bot/shot_chart_animator.rb` (replaces the stub class body from Task 1's file? No — Task 1 put the stub in `coord_normalizer.rb`; this task creates the orchestrator file separately and Ruby will reopen the class.)
- Test: `test/services/rod_the_bot/shot_chart_animator_test.rb`
- Create: `test/fixtures/files/test_shot_chart.mp4`

Note: To avoid double-defining the class, this file uses `class RodTheBot::ShotChartAnimator` to reopen — Ruby is fine with that.

- [ ] **Step 1: Create the test-env fixture MP4**

```bash
mkdir -p test/fixtures/files
# 1-byte placeholder is fine; tests don't inspect contents
printf '\0' > test/fixtures/files/test_shot_chart.mp4
```

- [ ] **Step 2: Write the failing tests**

Create `test/services/rod_the_bot/shot_chart_animator_test.rb`:

```ruby
require "test_helper"

class RodTheBot::ShotChartAnimatorTest < ActiveSupport::TestCase
  def test_short_circuits_in_test_env
    path = RodTheBot::ShotChartAnimator.new(game_id: 2024020477, through_period: 1).call
    assert_kind_of Pathname, path
    assert_equal "test_shot_chart.mp4", path.basename.to_s
  end

  def test_returns_nil_when_no_plottable_shots
    # Force the non-test branch but stub out the PBP fetch with an empty feed.
    Rails.env.stubs(:test?).returns(false)
    NhlApi.stubs(:fetch_pbp_feed).returns({"homeTeam" => {"id" => 1, "abbrev" => "HME"},
                                            "awayTeam" => {"id" => 2, "abbrev" => "AWY"},
                                            "plays" => []})
    result = RodTheBot::ShotChartAnimator.new(game_id: 1, through_period: 1).call
    assert_nil result
  end

  def test_idempotent_returns_existing_mp4
    Rails.env.stubs(:test?).returns(false)
    Dir.mktmpdir do |tmp|
      RodTheBot::ShotChartAnimator.any_instance.stubs(:output_dir).returns(Pathname.new(tmp))
      target = Pathname.new(tmp).join("p1.mp4")
      target.write("placeholder")

      # Stub the PBP fetch so even if the early-return fails the test would still see it
      NhlApi.stubs(:fetch_pbp_feed).returns({"homeTeam" => {"id" => 1, "abbrev" => "HME"},
                                              "awayTeam" => {"id" => 2, "abbrev" => "AWY"},
                                              "plays" => []})

      result = RodTheBot::ShotChartAnimator.new(game_id: 1, through_period: 1).call
      assert_equal target, result
    end
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `bin/rails test test/services/rod_the_bot/shot_chart_animator_test.rb`
Expected: All fail because `RodTheBot::ShotChartAnimator#call` doesn't exist yet.

- [ ] **Step 4: Implement the orchestrator**

Create `app/services/rod_the_bot/shot_chart_animator.rb`:

```ruby
require "mini_magick"
require "fileutils"
require "pathname"
require "tmpdir"

module RodTheBot
  class ShotChartAnimator
    INTRO_SECONDS = 1.0
    OUTRO_SECONDS = 3.0
    POP_SECONDS   = 0.3
    POP_FRAMES    = 4
    TOTAL_BUDGET  = 50.0
    FRAME_FPS     = 30
    MAX_VIDEO_BYTES = 50 * 1024 * 1024
    MAX_VIDEO_SECS  = 60

    TEAM_COLORS = {
      "ANA" => "#F47A38", "ARI" => "#8C2633", "BOS" => "#FFB81C", "BUF" => "#003087",
      "CGY" => "#D2001C", "CAR" => "#CC0000", "CHI" => "#CF0A2C", "COL" => "#6F263D",
      "CBJ" => "#002654", "DAL" => "#006847", "DET" => "#CE1126", "EDM" => "#FF4C00",
      "FLA" => "#C8102E", "LAK" => "#000000", "MIN" => "#154734", "MTL" => "#AF1E2D",
      "NSH" => "#FFB81C", "NJD" => "#CE1126", "NYI" => "#00539B", "NYR" => "#0038A8",
      "OTT" => "#C8102E", "PHI" => "#F74902", "PIT" => "#FCB514", "SJS" => "#006D75",
      "SEA" => "#001628", "STL" => "#002F87", "TBL" => "#002868", "TOR" => "#00205B",
      "UTA" => "#71AFE5", "VAN" => "#00205B", "VGK" => "#B4975A", "WSH" => "#C8102E",
      "WPG" => "#041E42"
    }.freeze

    DEFAULT_COLOR = "#444444"

    PERIOD_LABELS = {1 => "End of 1st", 2 => "End of 2nd", 3 => "End of 3rd", 4 => "End of OT"}.freeze

    def initialize(game_id:, through_period:)
      @game_id = game_id
      @through_period = through_period
    end

    def call
      return Pathname.new("test/fixtures/files/test_shot_chart.mp4") if Rails.env.test?

      target = output_path
      return target if target.exist?

      feed = NhlApi.fetch_pbp_feed(@game_id)
      shots = ShotExtractor.call(feed: feed, through_period: @through_period)
      return nil if shots.empty?

      home = feed["homeTeam"]
      away = feed["awayTeam"]
      home_color = TEAM_COLORS[home["abbrev"]] || DEFAULT_COLOR
      away_color = TEAM_COLORS[away["abbrev"]] || DEFAULT_COLOR

      prior, current = shots.partition { |s| s[:period] < @through_period }
      annotate_goal_numbers!(shots)

      frame_dir = output_dir.join("p#{@through_period}_frames")
      FileUtils.mkdir_p(frame_dir)

      rink_path = frame_dir.join("rink.png").to_s
      RinkRenderer.call(rink_path)

      sog_progression = compute_sog_progression(prior, current, home["id"], away["id"])
      concat_lines = []

      # Intro: prior shots only
      intro = render_frame(rink_path, frame_dir.join("intro.png").to_s,
                          prior_shots: prior, new_shots: [], new_shot_scale: 1.0,
                          active_caption: nil,
                          away_abbrev: away["abbrev"], home_abbrev: home["abbrev"],
                          away_color: away_color, home_color: home_color,
                          period_label: period_label,
                          away_sog: sog_progression[:start_away],
                          home_sog: sog_progression[:start_home])
      concat_lines << format_concat(intro, INTRO_SECONDS)

      revealed = []
      dwell = compute_dwell(current.size)

      current.each_with_index do |shot, i|
        revealed << shot
        sog = sog_progression[:after_each][i]

        # Pop frames
        POP_FRAMES.times do |k|
          scale = pop_scale(k)
          path = frame_dir.join("shot_#{i}_pop_#{k}.png").to_s
          render_frame(rink_path, path,
                      prior_shots: prior, new_shots: revealed, new_shot_scale: scale,
                      active_caption: shot[:time_in_period],
                      away_abbrev: away["abbrev"], home_abbrev: home["abbrev"],
                      away_color: away_color, home_color: home_color,
                      period_label: period_label,
                      away_sog: sog[:away], home_sog: sog[:home])
          concat_lines << format_concat(path, POP_SECONDS / POP_FRAMES)
        end

        # Settled frame, held for the dwell budget
        path = frame_dir.join("shot_#{i}_settled.png").to_s
        render_frame(rink_path, path,
                    prior_shots: prior, new_shots: revealed, new_shot_scale: 1.0,
                    active_caption: nil,
                    away_abbrev: away["abbrev"], home_abbrev: home["abbrev"],
                    away_color: away_color, home_color: home_color,
                    period_label: period_label,
                    away_sog: sog[:away], home_sog: sog[:home])
        concat_lines << format_concat(path, dwell)
      end

      # Outro: same final state, held longer
      outro_path = frame_dir.join("outro.png").to_s
      render_frame(rink_path, outro_path,
                  prior_shots: prior, new_shots: current, new_shot_scale: 1.0,
                  active_caption: nil,
                  away_abbrev: away["abbrev"], home_abbrev: home["abbrev"],
                  away_color: away_color, home_color: home_color,
                  period_label: period_label,
                  away_sog: sog_progression[:after_each].last&.dig(:away) || sog_progression[:start_away],
                  home_sog: sog_progression[:after_each].last&.dig(:home) || sog_progression[:start_home])
      concat_lines << format_concat(outro_path, OUTRO_SECONDS)

      concat_file = frame_dir.join("concat.txt")
      concat_file.write(concat_lines.join("\n"))

      stitch(concat_file, target)
      cleanup_frames(frame_dir, target)

      enforce_size_limit(target)
    rescue NhlApi::APIError => e
      Rails.logger.error "ShotChartAnimator: API error for game #{@game_id}: #{e.message}"
      nil
    end

    private

    def output_dir
      Pathname.new(Rails.root.join("tmp", "shot_charts", @game_id.to_s))
    end

    def output_path
      output_dir.tap { |d| FileUtils.mkdir_p(d) }.join("p#{@through_period}.mp4")
    end

    def period_label
      PERIOD_LABELS[@through_period] || "End of P#{@through_period}"
    end

    def render_frame(rink_path, out_path, **kwargs)
      FrameCompositor.compose(rink_path: rink_path, out_path: out_path, **kwargs)
      out_path
    end

    def annotate_goal_numbers!(shots)
      n = 0
      shots.each do |s|
        if s[:type] == "goal"
          n += 1
          s[:goal_number] = n
        end
      end
    end

    def compute_sog_progression(prior, current, home_id, away_id)
      start_away = prior.count { |s| s[:team_id] == away_id }
      start_home = prior.count { |s| s[:team_id] == home_id }
      after = []
      a, h = start_away, start_home
      current.each do |s|
        a += 1 if s[:team_id] == away_id
        h += 1 if s[:team_id] == home_id
        after << {away: a, home: h}
      end
      {start_away: start_away, start_home: start_home, after_each: after}
    end

    def compute_dwell(n)
      return 0 if n.zero?
      remaining = TOTAL_BUDGET - INTRO_SECONDS - OUTRO_SECONDS - (POP_SECONDS * n)
      [remaining / n, 0.4].max
    end

    def pop_scale(frame_index)
      # 4 frames: 0.6 → 1.3 → 1.1 → 1.0
      [0.6, 1.3, 1.1, 1.0][frame_index]
    end

    def format_concat(path, duration)
      "file '#{path}'\nduration #{format("%.3f", duration)}"
    end

    def stitch(concat_file, target)
      cmd = [
        "ffmpeg", "-y", "-f", "concat", "-safe", "0",
        "-i", concat_file.to_s,
        "-vf", "fps=#{FRAME_FPS},format=yuv420p",
        "-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p",
        target.to_s
      ]
      out, status = Open3.capture2e(*cmd)
      raise "ffmpeg failed (exit #{status.exitstatus}): #{out}" unless status.success?
    end

    def cleanup_frames(frame_dir, kept_mp4)
      Dir.glob(frame_dir.join("*.png")).each { |f| File.delete(f) }
      File.delete(frame_dir.join("concat.txt").to_s) if File.exist?(frame_dir.join("concat.txt").to_s)
    end

    def enforce_size_limit(target)
      size = File.size(target)
      duration = FFMPEG::Movie.new(target.to_s).duration rescue nil
      if size > MAX_VIDEO_BYTES || (duration && duration > MAX_VIDEO_SECS)
        Rails.logger.warn "ShotChartAnimator: rendered video exceeds limits " \
                          "(size=#{size}, dur=#{duration}). Skipping."
        File.delete(target)
        return nil
      end
      target
    end
  end
end
```

Add the `require "open3"` and `require "ffmpeg"`-equivalent if not autoloaded — `streamio-ffmpeg` autoloads as `FFMPEG`. Add `require "open3"` at the top of the file alongside the other requires.

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/services/rod_the_bot/shot_chart_animator_test.rb`
Expected: 3 tests, 0 failures. (The first test exercises the test-env short-circuit; the others stub out `Rails.env` and `NhlApi`.)

- [ ] **Step 6: Commit**

```bash
git add app/services/rod_the_bot/shot_chart_animator.rb \
        test/services/rod_the_bot/shot_chart_animator_test.rb \
        test/fixtures/files/test_shot_chart.mp4
git commit -m "feat: add ShotChartAnimator orchestrator service"
```

---

## Task 6: EndOfPeriodShotChartWorker

**Files:**
- Create: `app/workers/rod_the_bot/end_of_period_shot_chart_worker.rb`
- Test: `test/workers/end_of_period_shot_chart_worker_test.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/workers/end_of_period_shot_chart_worker_test.rb`:

```ruby
require "test_helper"

class RodTheBot::EndOfPeriodShotChartWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @game_id = 2024020477
  end

  def test_posts_video_when_service_returns_path
    fake_path = Pathname.new("test/fixtures/files/test_shot_chart.mp4")
    feed = {"homeTeam" => {"abbrev" => "EDM", "sog" => 21}, "awayTeam" => {"abbrev" => "VGK", "sog" => 17}}
    NhlApi.stubs(:fetch_pbp_feed).with(@game_id).returns(feed)
    RodTheBot::ShotChartAnimator.any_instance.stubs(:call).returns(fake_path)

    RodTheBot::EndOfPeriodShotChartWorker.new.perform(@game_id, 1)

    assert_equal 1, RodTheBot::Post.jobs.size
    args = RodTheBot::Post.jobs.first["args"]
    expected_text = <<~POST
      🏒 Shot chart through the 1st period.
      
      VGK: 17 SOG
      EDM: 21 SOG
    POST
    assert_equal expected_text, args[0]
    # Post.perform args: post, key, parent_key, embed_url, embed_images, video_file_path, root_key
    assert_equal fake_path.to_s, args[5]
  end

  def test_no_op_when_service_returns_nil
    NhlApi.stubs(:fetch_pbp_feed).returns({"homeTeam" => {}, "awayTeam" => {}})
    RodTheBot::ShotChartAnimator.any_instance.stubs(:call).returns(nil)

    RodTheBot::EndOfPeriodShotChartWorker.new.perform(@game_id, 1)

    assert_equal 0, RodTheBot::Post.jobs.size
  end

  def test_swallows_exceptions
    NhlApi.stubs(:fetch_pbp_feed).raises(StandardError, "boom")

    # Should not raise
    RodTheBot::EndOfPeriodShotChartWorker.new.perform(@game_id, 1)
    assert_equal 0, RodTheBot::Post.jobs.size
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/workers/end_of_period_shot_chart_worker_test.rb`
Expected: All 3 fail with `NameError: uninitialized constant RodTheBot::EndOfPeriodShotChartWorker`.

- [ ] **Step 3: Implement the worker**

Create `app/workers/rod_the_bot/end_of_period_shot_chart_worker.rb`:

```ruby
module RodTheBot
  class EndOfPeriodShotChartWorker
    include Sidekiq::Worker
    sidekiq_options retry: false

    PERIOD_NAMES = {1 => "1st", 2 => "2nd", 3 => "3rd", 4 => "OT"}.freeze

    def perform(game_id, period_number)
      feed = NhlApi.fetch_pbp_feed(game_id)
      home = feed["homeTeam"] || {}
      away = feed["awayTeam"] || {}

      path = RodTheBot::ShotChartAnimator.new(
        game_id: game_id,
        through_period: period_number
      ).call
      return if path.nil?

      post_text = format_post(home, away, period_number)
      RodTheBot::Post.perform_async(
        post_text,           # post
        nil,                 # key
        nil,                 # parent_key
        nil,                 # embed_url
        [],                  # embed_images
        path.to_s,           # video_file_path
        nil                  # root_key
      )
    rescue NhlApi::APIError => e
      Rails.logger.error "EndOfPeriodShotChartWorker: API error for game #{game_id}: #{e.message}"
    rescue => e
      Rails.logger.error "EndOfPeriodShotChartWorker: Unexpected error for game #{game_id}: #{e.class} - #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
    end

    private

    def format_post(home, away, period_number)
      label = PERIOD_NAMES[period_number] || "P#{period_number}"
      <<~POST
        🏒 Shot chart through the #{label} period.

        #{away.fetch("abbrev", "AWY")}: #{away.fetch("sog", 0)} SOG
        #{home.fetch("abbrev", "HME")}: #{home.fetch("sog", 0)} SOG
      POST
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/workers/end_of_period_shot_chart_worker_test.rb`
Expected: 3 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/workers/rod_the_bot/end_of_period_shot_chart_worker.rb \
        test/workers/end_of_period_shot_chart_worker_test.rb
git commit -m "feat: add EndOfPeriodShotChartWorker"
```

---

## Task 7: Hook into EndOfPeriodWorker

**Files:**
- Modify: `app/workers/rod_the_bot/end_of_period_worker.rb`
- Modify: `test/workers/end_of_period_worker_test.rb`

- [ ] **Step 1: Update the test to assert the new enqueue**

Edit `test/workers/end_of_period_worker_test.rb`. Locate the `test_perform` method and the existing assertions:

```ruby
assert_equal 1, RodTheBot::Post.jobs.size
assert_equal 1, RodTheBot::EndOfPeriodStatsWorker.jobs.size
```

Add immediately below them:

```ruby
assert_equal 1, RodTheBot::EndOfPeriodShotChartWorker.jobs.size
shot_chart_args = RodTheBot::EndOfPeriodShotChartWorker.jobs.first["args"]
assert_equal [@game_id, 1], shot_chart_args
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/workers/end_of_period_worker_test.rb`
Expected: Failure on the new assertion (`Expected: 1, Actual: 0`).

- [ ] **Step 3: Add the enqueue line**

Edit `app/workers/rod_the_bot/end_of_period_worker.rb`. Locate this line:

```ruby
RodTheBot::EndOfPeriodStatsWorker.perform_in(60, game_id, period_descriptor.fetch("number", 1))
```

Add immediately after it:

```ruby
RodTheBot::EndOfPeriodShotChartWorker.perform_in(75, game_id, period_descriptor.fetch("number", 1))
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/workers/end_of_period_worker_test.rb`
Expected: 2 tests, 0 failures.

- [ ] **Step 5: Run the full test suite as a sanity check**

Run: `bin/rails test`
Expected: All tests pass. If anything breaks, fix it before committing.

- [ ] **Step 6: Commit**

```bash
git add app/workers/rod_the_bot/end_of_period_worker.rb \
        test/workers/end_of_period_worker_test.rb
git commit -m "feat: enqueue EndOfPeriodShotChartWorker from end-of-period flow"
```

---

## Self-review notes

- **Spec coverage:**
  - Static rink → Task 3 (programmatic instead, deviation called out at top of plan).
  - Service `RodTheBot::ShotChartAnimator` → Task 5.
  - Worker `RodTheBot::EndOfPeriodShotChartWorker` → Task 6.
  - Hook into `EndOfPeriodWorker` with 75s delay → Task 7.
  - Coordinate normalization (home attacks right) → Task 1.
  - PBP filtering and chronological sort → Task 2.
  - Frame strategy (intro/pop/settled/outro) → Task 5.
  - Visual treatment (markers, opacity, captions, overlay) → Task 4.
  - Shootout exclusion → relies on existing `return if periodType == "SO"` in `EndOfPeriodWorker`; no new code needed.
  - Missing-coord shots dropped → Task 2 test `test_drops_shots_with_missing_coordinates`.
  - Render failure caught and logged → Task 6 `test_swallows_exceptions`; service-level rescue in Task 5.
  - File size / duration guard → Task 5 `enforce_size_limit`.
  - Idempotency → Task 5 `test_idempotent_returns_existing_mp4`.
  - Test-env short-circuit → Task 5 `test_short_circuits_in_test_env`.

- **No placeholders.**
- **Type/method consistency:**
  - `CoordNormalizer.normalize(x:, y:, home_defending_side:)` — used by `ShotExtractor` and (transitively) elsewhere.
  - `CoordNormalizer.to_canvas(x, y)` — positional args, used in `FrameCompositor`.
  - `ShotExtractor.call(feed:, through_period:)` — keyword args.
  - `RinkRenderer.call(out_path)` — positional arg.
  - `FrameCompositor.compose(...)` — keyword args, all sites in the orchestrator pass the same set.
  - `ShotChartAnimator.new(game_id:, through_period:).call` — matches spec and worker call site.
  - `RodTheBot::Post.perform_async(post, key, parent_key, embed_url, embed_images, video_file_path, root_key)` — verified against `app/workers/rod_the_bot/post.rb`.

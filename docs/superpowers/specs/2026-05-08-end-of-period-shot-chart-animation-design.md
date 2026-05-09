# End-of-Period Shot Chart Animation

## Summary

At the end of each regulation period and overtime, the bot posts an MP4 animation
to the game thread showing every shot-on-goal and goal so far in the game. New
shots from the just-completed period animate in chronologically; shots from
prior periods are already on the rink at frame zero. Shootouts are excluded.

## Goals

- Add a visual, gameday-only feature that turns NHL play-by-play coordinate data
  into a recognizable shot map for fans.
- Reuse the existing post/threading pipeline and existing media-embed support.
- No new external dependencies — `mini_magick`, `ffmpeg`, `imagemagick`, and
  `streamio-ffmpeg` are already in the image.

## Non-Goals

- Heat maps, Corsi (blocked/missed shots), per-player charts, historical comparisons.
- Shootout visualization (no coordinates exist for SO shots).
- Live in-period updates — only fires at end-of-period.
- Reusing watch-party-games' JS rendering at runtime; we mirror the visual concept
  but render server-side in Ruby.

## Architecture

Three new files, plus one line added to an existing worker.

### 1. Static rink asset

`app/assets/images/shot_chart/rink.png` — hand-crafted, 1200×510 (matches
watch-party-games' canvas, NHL regulation 200×85 ft aspect ratio). Includes
ice surface, goal lines, blue lines, center red line/circle, faceoff dots and
circles, and goal creases. Versioned in git as a normal asset; not regenerated
at runtime.

### 2. `RodTheBot::ShotChartAnimator` service

Path: `app/services/rod_the_bot/shot_chart_animator.rb`

Public API:

```ruby
RodTheBot::ShotChartAnimator.new(game_id:, through_period:).call
# → Pathname to MP4, or nil if the render was skipped
```

Responsibilities:

- Pull PBP via `NhlApi.fetch_pbp_feed`.
- Filter to plottable shots (see Data section).
- Normalize coordinates across period flips.
- Render keyframes by compositing markers and overlays over `rink.png`.
- Stitch frames into an MP4 with ffmpeg.
- Return the MP4 path, or nil if there is nothing to animate.

Idempotent: if `tmp/shot_charts/{game_id}/p{N}.mp4` already exists, return it
without re-rendering.

In `Rails.env.test?` the service short-circuits to a fixture MP4 path (mirrors
`NhlVideoDownloadService#mock_video_path`).

### 3. `RodTheBot::EndOfPeriodShotChartWorker`

Path: `app/workers/rod_the_bot/end_of_period_shot_chart_worker.rb`

Sidekiq worker, args `(game_id, period_number)`.

- Calls the service.
- If the service returns a path, calls
  `RodTheBot::Post.perform_async(post_text, key, parent_key, nil, [], path.to_s, root_key)`
  so the chart threads under the game like every other reply post. Threading
  args follow the existing reply pattern in the codebase.
- If the service returns nil, the worker no-ops.
- Catches all exceptions, logs at error level, and exits cleanly. Sidekiq retry
  is disabled for this worker — a missing chart is better than a duplicated or
  broken one.

### 4. Hook into existing flow

In `app/workers/rod_the_bot/end_of_period_worker.rb`, alongside the existing
`EndOfPeriodStatsWorker.perform_in(60, …)` line:

```ruby
RodTheBot::EndOfPeriodShotChartWorker.perform_in(75, game_id, period_descriptor.fetch("number", 1))
```

The 75-second delay puts the chart post after the stats post in the thread, and
gives the PBP feed time to settle. The existing
`return if play["periodDescriptor"]["periodType"] == "SO"` guard in
`EndOfPeriodWorker` remains untouched, which automatically excludes shootouts
from the shot chart trigger as well.

## Data Flow

1. Pull `NhlApi.fetch_pbp_feed(game_id)`.
2. Filter `plays` where:
   - `typeDescKey ∈ {"shot-on-goal", "goal"}`
   - `periodDescriptor.number ≤ through_period`
   - `details.xCoord` and `details.yCoord` are both present
3. For each shot, capture: `eventId`, `period`, `timeInPeriod`, `xCoord`,
   `yCoord`, `typeDescKey`, `eventOwnerTeamId`, `homeTeamDefendingSide`
   (per-period), and for goals the running `awayScore`/`homeScore`.
4. Sort by `(period, timeInPeriod)` ascending.
5. Read team metadata from `homeTeam`/`awayTeam` in the PBP feed: `id`,
   `abbrev`, `logo` URL.

### Coordinate normalization

NHL coords are absolute and teams switch ends each period. Canonical orientation:
**home team always attacks right.**

For any shot in a period where `homeTeamDefendingSide == "right"` (i.e., home
attacks left that period), flip both coords: `x' = -x, y' = -y`. After
normalization, all home-team shots cluster on the right end of the rink and
all away-team shots cluster on the left, regardless of which period they came
from. (This matches the approach in watch-party-games' `display.js`.)

### Canvas mapping

Linear after normalization:

```
canvas_x = (nhl_x + 100)  / 200  * 1200
canvas_y = (nhl_y + 42.5) / 85   * 510
```

### Team colors

Pulled from existing team-color config in the bot. If no such config exists yet,
add a small constant map in the service keyed by team abbrev (away primary,
home primary). Confirmed during implementation.

## Animation

### Frame strategy

Keyframe-based — not 30fps render-everything. For a typical period with ~20 new
plottable shots:

- 1 intro frame: cumulative state from prior periods, no new shots yet. Held ~1s.
- Per new shot: 4 pop-in frames (scale 0 → 1.3 → 1.0 over ~0.3s), then 1 settled
  frame held to consume the dwell budget.
- 1 outro frame: final state. Held ~3s.

Total budget: ~50 seconds. Inter-shot dwell scales:
`(50 − intro − outro − 0.3 × N) / N`. For low-shot OT periods the animation
naturally comes in well under 50s — that is fine, no padding.

Frames are PNGs under `tmp/shot_charts/{game_id}/p{N}/`. Stitched via ffmpeg's
concat demuxer with per-frame durations.

### Visual treatment

- **Shot on goal** — solid filled circle, ~14px diameter, team primary color.
  70% opacity for prior-period shots, 100% for current period.
- **Goal** — filled star or larger circle (~22px) with white outline, 100%
  opacity, goal sequence number rendered inside (1, 2, 3…). Team color fill.
- **Pop-in** — only on new shots being revealed in the current period. Old shots
  appear at full opacity at the intro frame, no animation.
- **Timestamp caption** — when a new shot pops in, a tiny `MM:SS` label fades
  in next to it for ~1s then fades out, leaving just the marker.

### Overlay (minimal)

- Away team logo top-left, home team logo top-right (matching their attacking
  ends after normalization).
- Period label bottom-center: `End of 1st`, `End of 2nd`, `End of 3rd`,
  `End of OT`. Static throughout the video.
- Shots-on-goal legend in a corner: `AWY 12 — HME 9` cumulative through this
  period. Static.

### Post text

```
Shot chart through the {period_name}.

{AWAY_ABBR}: {away_sog} SOG
{HOME_ABBR}: {home_sog} SOG
```

## Edge Cases

- **Shootouts** — excluded by the existing `return if periodType == "SO"` in
  `EndOfPeriodWorker`. No code in the new worker or service needs to know
  about SO.
- **Missing coordinates** — single shots with nil `xCoord`/`yCoord` are skipped
  silently and logged at debug level. The render still proceeds.
- **PBP not yet caught up** — the 75s enqueue delay should cover it. If the
  end-of-period play hasn't arrived, render with what's available — same
  contract as `EndOfPeriodStatsWorker`. No retry.
- **Render failure** — caught in the worker, logged with the existing
  `Rails.logger.error` pattern, no Bluesky post made. Sidekiq retry disabled.
- **File size / duration guard** — after ffmpeg, if the MP4 exceeds 50 MB or
  60 s, log a warning and skip the post. Mirrors the check in
  `NhlVideoDownloadService`.
- **Idempotency** — same `(game_id, period_number)` produces the same MP4 path.
  If it exists, return without re-rendering.
- **Disk hygiene** — frame PNGs deleted after successful post. The MP4 is kept
  ~24h for re-post needs. Follow whatever `tmp/` cleanup convention already
  exists; if none, leftovers are harmless and Docker volume recycling handles
  it.

## Testing

- Service tests: recorded PBP fixture; assert correct shot count and ordering
  after coord normalization, assert correct number of keyframes scheduled,
  assert the constructed ffmpeg command. Do not actually invoke ffmpeg in CI.
- Worker tests: assert the worker calls the service, asserts the resulting
  `RodTheBot::Post.perform_async` call has the right post text, threading args,
  and `video_file_path`. Service is stubbed to return a fixture MP4 path.
- `EndOfPeriodWorker` test: assert the new
  `EndOfPeriodShotChartWorker.perform_in(75, …)` enqueue is added without
  removing or breaking any existing enqueues.

## Open Questions / Implementation-Time Decisions

- Whether the bot already has a team-color lookup, or whether we add a small
  constant map keyed by team abbrev in the service.
- Exact ffmpeg invocation (raw shell-out vs `streamio-ffmpeg` API for concat
  demuxer with per-frame durations) — pick whichever is cleaner during build.
- Whether the goal star marker should display the goal number, the scorer's
  jersey number, or nothing — start with goal number, refine if it looks busy.

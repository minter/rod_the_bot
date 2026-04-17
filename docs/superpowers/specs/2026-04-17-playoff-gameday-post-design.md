# Playoff Gameday Post Design

## Goal

Update the daily gameday post so that during the NHL postseason it reflects the
playoff context — series matchup, seed labels, round, game number, and current
series state — instead of the regular-season format that shows records and
division rank.

## Current Behavior

`RodTheBot::Scheduler#perform` (`app/workers/rod_the_bot/scheduler.rb`) builds a
gameday post when the configured team has a game today. Today the template
branches twice:

- **Preseason** — team names, time, venue, TV (no records)
- **Otherwise** — team names + W-L-OT record + division rank, time, venue, TV

During the playoffs the "otherwise" branch runs, so the post shows
regular-season records even though we are posting a playoff game.

## Target Behavior

Add a third branch for `NhlApi.postseason?`. The playoff gameday post:

- Headline: `🗣️ It's a {Team} Playoff Gameday!`
- Status line (new, immediately under the headline):
  `Round {N}, Game {M} — {series status}`
  - Uses `seriesStatus.round` and `seriesStatus.gameNumberOfSeries` from the
    game payload
  - Series status wording reuses the strings already produced by
    `YesterdaysScoresWorker#format_series_status` for consistency:
    - `Series tied {wins}-{wins}` when scores are equal
    - `{abbrev} leads {wins}-{wins}` when one team is ahead
- Team blocks: each team name is prefixed with its seed label from
  `NhlApi.playoff_seed_labels` (e.g., `(M1) Carolina Hurricanes`,
  `(WC2) Ottawa Senators`). Regular-season record lines are removed.
- Time, venue, and TV lines: unchanged.

### Example (Game 1 of CAR vs. OTT)

```
🗣️ It's a Carolina Hurricanes Playoff Gameday!

Round 1, Game 1 — Series tied 0-0

(WC2) Ottawa Senators

at

(M1) Carolina Hurricanes

⏰ 7 PM EDT
📍 Lenovo Center
📺 ESPN, FDSNSO
```

### Example (mid-series)

```
🗣️ It's a Carolina Hurricanes Playoff Gameday!

Round 1, Game 4 — CAR leads 2-1

(WC2) Ottawa Senators

at

(M1) Carolina Hurricanes

⏰ 7 PM EDT
📍 Lenovo Center
📺 ESPN
```

## Scope

### In scope

- A new postseason branch in the scheduler's gameday-post builder.
- Reusing `NhlApi.playoff_seed_labels` (added in the previous commit).
- Rendering the series status string (round, game number, standings).
- Unit tests for the new branch.

### Out of scope

- Any change to downstream workers that the gameday block schedules
  (`GameStream`, `PlayerStreaksWorker`, `SeasonStatsWorker`,
  `UpcomingMilestonesWorker`, `schedule_edge_posts`). They already switch on
  `postseason?` where needed.
- Any change to the preseason or regular-season branches.
- Any change to `TodaysScheduleWorker` or `YesterdaysScoresWorker` (they
  already render playoff context).

## Data Sources

- `@game["seriesStatus"]` — supplied by `NhlApi.todays_game`:
  - `round` (integer, e.g., `1`)
  - `gameNumberOfSeries` (integer, e.g., `1`)
  - `topSeedTeamAbbrev`, `topSeedWins`
  - `bottomSeedTeamAbbrev`, `bottomSeedWins`
- `NhlApi.playoff_seed_labels` — `{abbrev => "M1" / "WC2" / etc.}` map derived
  from `/standings/now`.

## Design Details

### Scheduler branch structure

```
gameday_post = if NhlApi.preseason?
  preseason_template(...)
elsif NhlApi.postseason?
  playoff_template(...)
else
  regular_season_template(...)
end
```

### Helper placement

Add private helpers on `Scheduler`:

- `playoff_status_line(game)` — returns `"Round {N}, Game {M} — {series status}"`.
- `playoff_series_state(series_status)` — returns `"Series tied 0-0"` or
  `"CAR leads 2-1"` given a `seriesStatus` hash.
- `seed_prefix(abbrev, seed_labels)` — returns `"(M1) "` or `""` (same
  pattern used in `PostseasonSeriesWorker`).

`playoff_seed_labels` is fetched once inside the gameday-post builder and
passed to the template.

### Fallback behavior

- **Seed labels missing** (standings API failure): omit the `(M1) ` prefix,
  just render the team name.
- **`seriesStatus` missing from game payload**: fall back to the regular-season
  template for that game. This is defensive — the NHL API has reliably
  populated `seriesStatus` for playoff games historically, but we do not want a
  crash if the field is absent.

## Character Budget

Bluesky posts cap at 300 characters. A worst-case playoff gameday post with
long team names, 3-TV broadcast, and seed labels is projected well under the
cap (Game 1 preview above is ~225 chars pre-hashtag). No special handling
needed.

## Testing

Unit test coverage for the new branch:

1. Postseason branch produces the `Playoff Gameday!` headline.
2. Postseason branch includes the `Round N, Game M — …` status line.
3. Postseason branch prefixes team names with seed labels when available.
4. Postseason branch gracefully omits seed labels when the map is empty.
5. Postseason branch falls back to the regular-season template when
   `seriesStatus` is absent.

Existing scheduler tests that already stub `postseason?` / `preseason?` /
`offseason?` continue to exercise the other branches.

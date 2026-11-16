# Morning EDGE game recap

## Intent

Post a short EDGE tracking recap thread the morning after every tracked-team game. The bot's EDGE posts today are all pregame season aggregates; this is the first one about a specific game.

## What the data allows

Measured on 2026-11-14 and 2026-11-15: EDGE per-game data arrives as one nightly batch around 2:00 to 2:30 am Eastern, after the night's last game. It is not available the same night.

Per game, EDGE provides only:

- Team skating distance with even-strength, power-play, and penalty-kill splits (`edge/team-skating-distance-detail`, `skatingDistanceLast10`).
- Each skater's distance and ice time (`edge/skater-skating-distance-detail`, one request per skater).
- The team's season top-10 hardest shots and top-10 skating speeds (`edge/team-shot-speed-detail`, `edge/team-skating-speed-detail`). A shot or speed from the game appears only if it makes the list.

Zone time, shot location, and burst counts are season aggregates and cannot be attributed to a game.

## Goals

- A thread per game, every game, from the daily 10 am scheduler run: two posts on an ordinary night, three when the game set season marks.
- Root, always: team distance with its rank among recent games, the opponent's distance, and the situational split.
- Reply, always: the three skaters who covered the most ice.
- Reply, only when present: every shot and speed from the game that is on the team's season top-10 lists.

## Non-goals

- Same-night posting.
- Goalie numbers, images, or headshots.
- Opponent skaters or opponent season marks.
- Posting for preseason games.

## Anti-goals

- Posting numbers from the wrong game. Entries are matched by game ID parsed from `gameCenterLink`, never by date alone or list position.
- Presenting a season aggregate as a game figure.
- Padding: a post with nothing to say is skipped, not filled.

## Post format

Example built from the 2026-11-14 game (opponent distance and the third skater's name are placeholders):

```text
⛸️ EDGE recap: Hurricanes vs. Kraken

Hurricanes skated 45.28 mi (7th most in their last 10 games)
Kraken: 44.90 mi

Even strength 39.58 · Power play 3.48 · Penalty kill 2.22
```

```text
⛸️ Most ice covered:

#19 K'Andre Miller: 3.08 mi in 21:41
#20 Sebastian Aho: 2.94 mi in 18:50
#00 Third Skater: 2.77 mi in 16:55
```

```text
📈 New on the Hurricanes' season top 10:

💥 #4 Shayne Gostisbehere: 91.98 mph shot (6th hardest)
💥 #26 Sean Walker: 91.32 mph shot (8th hardest)
⚡ #74 Jaccob Slavin: 22.37 mph (10th fastest)
```

Rules:

- The title reads "Away at Home" from the tracked team's side: "Hurricanes vs. Kraken" at home, "Hurricanes at Kraken" on the road.
- The rank phrase is omitted when fewer than three games are in the list, and reads "their last N games" when fewer than ten. First and last rank read "most" and "fewest"; ordinals otherwise.
- The opponent line is omitted when the opponent's data is unavailable.
- The split line omits a situation with zero ice time.
- Season-mark lines are ordered shots first, then speeds, each by season rank. Top-of-list entries read "hardest" / "fastest" without an ordinal.
- The season-marks post is skipped until the team has five games in its recent-games list, because early in a season (or a playoff run) nearly every shot makes the top 10.
- Each post must fit the Bluesky limit after the team hashtags. The season-marks post drops lines from the end until it fits.

## Approaches

1. **Thread that grows with the material (chosen).** Team post and skater post always, season-marks post when earned. Costs about 18 skater requests plus one opponent request per game day.
2. **Single compact post.** Distance, one skater, best shot and best speed in one post. Superseded: it hid the second top-10 shot and gave only one skater.
3. **Only when notable.** Post only when a shot or speed cracks the top 10. Rejected: the top-10 lists harden as the season goes on and the post would go quiet.

## Design

- **Client.** Add `team_skating_distance_detail` to `Nhl::EdgeClient::ENDPOINTS` (six-hour TTL). The other three endpoints are already there. Requests pass `game_id:` so playoff games read playoff data.
- **Domain service.** `RodTheBot::EdgeRecap::GameData` takes the raw payloads (team distance, opponent distance, team shot speed, team skating speed, and a player-ID-to-payload hash of skater distance) plus the game ID, and returns a normalized result: team distance with splits, rank and list size, opponent distance, skaters ordered by distance (player ID, distance, ice time), and season marks (kind, player ID, speed, season rank). Returns nil when the team list does not contain the game. Pure; no network.
- **Formatter.** `RodTheBot::EdgeRecap::Formatter` takes that result, a player-ID-to-display-name lookup, team names, and home/away, and returns the array of post texts, applying the rules above.
- **Worker.** `RodTheBot::EdgeGameRecapWorker#perform(attempt = 0)`:
  - Finds yesterday's tracked-team game via `Nhl::ScheduleClient.todays_game(date: yesterday)` using the configured time zone. Returns if there is none, it is preseason, or the game was not played to a final.
  - Gets the skaters who played from `Nhl::GameClient.boxscore`, and identities from `Nhl::PlayerDirectory.for_game(game_id)` using `name_with_number`.
  - Fetches the team payloads, the opponent distance payload, and one distance payload per skater. This loop is explicit and bounded by the dressed skaters.
  - Enqueues through `RodTheBot::PostThread.enqueue` with key `edge_recap_<game_id>`.
- **Scheduler.** `RodTheBot::Scheduler` enqueues the worker every in-season morning, after yesterday's scores.

## Failure behavior

- **Data not there yet.** If the team list lacks the game, reschedule in 30 minutes, at most six times (10 am to 1 pm). On exhaustion, warn with the game ID and stop.
- **Double runs.** A `SET NX` claim per game with a TTL is taken just before enqueuing the thread, so a rerun or overlapping chain cannot post twice. The claim is released if enqueuing raises.
- **A skater request fails or lacks the game.** Skip that skater. If no skater has data, the skater post is skipped.
- **Opponent request fails.** Warn and omit the opponent line.
- **Team distance request fails.** `retry_job` with `game_id` and `operation: "edge_game_recap"`.
- **Shot or speed request fails.** Warn and skip the season-marks post.

## Testing

- `test/services/nhl`: cassette for `team-skating-distance-detail`.
- `test/services/rod_the_bot/edge_recap`: `GameData` and `Formatter` with small synthetic payloads: full thread, no season marks, short early-season list, extremes, missing game, wrong-game entries ignored, missing opponent, zero power-play time, over-length trimming.
- `test/workers/rod_the_bot`: no game yesterday, preseason, data-missing reschedule and exhaustion, skater failure skipped, claim prevents a second thread, thread key.

## Left to the builder

- Exact Redis key names and TTLs.

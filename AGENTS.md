# AGENTS.md

This file defines the architectural and engineering expectations for changes to Rod The Bot. It applies to the entire repository.

## Project purpose

Rod The Bot is a Rails 8.1 and Sidekiq application that reads NHL data, detects game events, builds Bluesky posts, and manages media and threaded replies. Redis stores live-game state, deduplication keys, and posting relationships.

The configured Ruby version is defined in `mise.toml`. Use the project runtime rather than the macOS system Ruby:

```sh
mise exec -- bundle exec rails test
```

## Architectural boundaries

Keep the dependency direction:

```text
External NHL/media APIs
        ↓
Focused clients and normalized contracts
        ↓
Domain, detection, and presentation services
        ↓
Sidekiq orchestration workers
        ↓
RodTheBot::Post / RodTheBot::PostThread
```

Do not move raw response interpretation, presentation logic, or reusable domain calculations back into workers.

### NHL clients

All NHL JSON requests must go through a focused class under `app/services/nhl`.

- Add an operation to the most relevant existing client when possible.
- Add a focused client when an endpoint represents a genuinely new API area.
- Do not call NHL endpoints directly with `HTTParty`, `Net::HTTP`, or browser automation from a worker.
- Use `Nhl::Client#get_json` for shared timeout and error behavior.
- Raise `Nhl::RequestError` for HTTP, network, timeout, and response-parsing failures.
- Normalize stable response contracts at the client boundary. Downstream code should not repeatedly reinterpret the same raw fields.
- Include the endpoint or resource context in errors.

Media transports such as EDGE replay JSON, logos, video manifests, and browser-discovered streams may use specialized services. They must still define explicit timeouts, safe command invocation, cleanup behavior, and contextual errors.

### Player identity

Never independently concatenate NHL player names, consume endpoint display abbreviations as canonical names, or interpret sweater-number field variants in workers.

Use:

- `Nhl::PlayerIdentity` for normalized player metadata and display variants.
- `Nhl::PlayerDirectory.for_game(game_id)` for game-specific identity and sweater numbers.
- `Nhl::PlayerDirectory.for_team(abbreviation)` for current-team features.
- `PlayerDirectory#resolve` only when an explicit cached player-landing fallback is appropriate.

The game roster is authoritative for game-related posts. This prevents current landing data from overwriting the team or sweater number worn in a historical or live game.

Select presentation deliberately:

- `name_with_number` when a reliable sweater number is available and useful.
- `full_name` when a source legitimately lacks a number or the post is a compact leaderboard.
- `abbreviated_name` only for an intentionally compact presentation such as scratches.

Do not recreate legacy player hashes or introduce another permissive player formatter.

### Workers

Workers orchestrate. A worker may:

- Fetch through focused clients.
- Resolve normalized identities.
- Check deduplication or live-game state.
- Invoke domain and presentation services.
- Schedule follow-up jobs.
- Enqueue posts and threads.

Workers should not contain large formatting templates, reusable calculations, endpoint normalization, or complex state machines. Extract those into a service with focused tests.

Keep `perform` arguments JSON-serializable. Treat an existing Sidekiq signature as an operational interface; change it intentionally and account for already-enqueued jobs when relevant.

### Domain and presentation services

Services should have narrow inputs and deterministic outputs where possible.

- Detection services decide what happened.
- Evaluators and analyzers calculate domain results.
- Formatters and post builders construct presentation.
- Schedulers produce timing decisions.
- Media services source, render, encode, and clean up files.

Do not hide network requests inside formatters. Pass normalized data or inject callable dependencies when a calculation needs external data.

### Posting and threading

- Use `RodTheBot::Post` as the Bluesky posting boundary.
- Use `RodTheBot::PostThread` for shared splitting, root creation, and reply chaining.
- Do not recreate thread key, parent key, or reply sequencing mechanics in individual workers.
- Preserve post deduplication and last-reply tracking when adding replies to game-event threads.
- Keep Bluesky character limits and automatically appended team hashtags in mind.

## Error and retry policy

Classify failures instead of rescuing every exception and returning success.

### Retryable failures

Network failures, NHL request failures, and unexpected processing failures should normally be passed to `WorkerErrorHandling#retry_job`. This logs searchable context and re-raises the original exception so Sidekiq can retry it and eventually place persistent failures in its dead set.

Include useful identifiers:

- `game_id`
- `play_id`
- `player_id`
- `period`
- `operation`
- relevant endpoint or media path

### Temporarily unavailable data

NHL data that is expected to appear later may use an explicit bounded reschedule. Define:

- A maximum retry count or maximum elapsed time.
- A fixed or intentional backoff interval.
- An exhaustion warning containing the relevant identifiers.
- Deduplication behavior that prevents concurrent polling chains.

Do not combine manual rescheduling with raising for Sidekiq on the same failure path unless duplicate retries are explicitly prevented.

### Permanent malformed input

Structurally invalid events that cannot become valid should use `discard_job` with contextual logging. Examples include missing goal or penalty details, missing period descriptors, and malformed final three-star arrays.

Do not silently coerce malformed data into a plausible public post.

### Optional enhancements

Optional images, headshots, media cleanup, and similar enhancements may warn and continue when the underlying text post remains valid. A failed primary post, required media operation, or state transition must not be swallowed.

## Redis and concurrency

- Use atomic Redis operations such as `SET ... NX` for deduplication and claims.
- Every temporary key must have an intentional expiration.
- Include game, event, team, and player identifiers in keys where needed to prevent collisions.
- Separate detection/claim from commit when state must not advance before the downstream work succeeds.
- Preserve source media or replay data when encoding fails.

## Caching

- Cache normalized contracts rather than repeatedly fetching or interpreting the same response.
- Game and team player directories currently use six-hour TTLs.
- Keys must include the resource identity, such as game ID, team abbreviation, player ID, date, or season.
- Do not use a current player landing response to override game-specific identity.
- Avoid hidden per-player fallback loops that create N+1 requests.

## Media safety

- Pass command arguments as arrays; never interpolate remote URLs or paths into shell commands.
- Clean temporary generated media after successful use and after failed posting where ownership permits.
- Do not delete source inputs when encoding fails.
- Validate downloaded paths and handle missing downloads before opening them.
- Put browser and external-process cleanup in `ensure` blocks.
- Preserve existing file-size and duration limits for Bluesky video.

## Testing

Every behavior change requires proportionate coverage.

### Test placement

- NHL client contract tests: `test/services/nhl`
- Domain and formatter tests: `test/services/rod_the_bot`
- Worker orchestration tests: `test/workers/rod_the_bot`

Prefer focused service tests over testing private worker methods. Worker tests should verify scheduling, posting, retry/discard decisions, state changes, and dependency coordination.

### VCR

Use VCR when real NHL behavior or response shape materially matters.

- Reuse an existing cassette when it represents the needed endpoint and scenario.
- Record a focused cassette when introducing a new NHL contract.
- Do not use VCR for pure formatters, detectors, or state machines that accept normalized input.
- Avoid `record: :new_episodes` unless intentionally updating a cassette.
- Do not make tests silently depend on live network access.
- Run `mise exec -- ruby vendor/find_unused_vcr_cassettes.rb` after cassette changes.

Small synthetic fixtures are appropriate for malformed responses, boundary conditions, pure formatting, and deterministic state transitions. Keep player IDs and associated names internally consistent unless the test explicitly verifies canonical resolution over contradictory endpoint text.

### Required verification

Run focused tests while developing, then before handoff run:

```sh
git diff --check
PARALLEL_WORKERS=1 mise exec -- bundle exec rails test
mise exec -- ruby vendor/find_unused_vcr_cassettes.rb
```

Serial execution avoids the Bundler temporary-home cleanup race that can occur in restricted environments. Existing skipped tests should be reported and not silently increased.

## Change hygiene

- Preserve unrelated user changes in a dirty worktree.
- Remove obsolete helpers, compatibility branches, tests, and cassettes when a migration makes them unnecessary.
- Backward compatibility is not required unless a specific operational interface or already-enqueued Sidekiq job makes it relevant.
- Do not add pass-through abstractions that merely rename an existing call.
- Keep comments focused on why behavior exists; remove stale migration commentary.
- Update this file when introducing a new architectural boundary or changing an established policy.

## Completion checklist

Before considering a change complete, confirm:

- External requests use the correct focused boundary.
- Workers retain orchestration rather than domain/presentation logic.
- Player output uses `PlayerIdentity`/`PlayerDirectory` intentionally.
- Retry, reschedule, discard, and optional-failure behavior is explicit.
- Redis writes are atomic where required and have suitable TTLs.
- Media ownership and cleanup behavior are safe.
- Focused and full tests pass.
- VCR inventory remains clean.
- No obsolete compatibility code remains after the migration.

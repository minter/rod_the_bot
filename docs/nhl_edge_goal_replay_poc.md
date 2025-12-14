# NHL EDGE Goal Replay PoC (Fetch → Render → MP4)

### Why this document exists
This is a short “memory” doc for the work around NHL EDGE goal visualizer data and the `edge_replay_poc.rb` script in this repo. It captures what we learned about where the data lives, how to fetch it reliably, the schema we observed, and how we render an MP4 from it.

---

### Key discovery: NHL.com’s “EDGE | Goal Visualizer” is client-side rendering
The “Goal Visualizer” shown on NHL.com Gamecenter is rendered in the browser from a raw tracking payload hosted at `wsr.nhle.com`.

- **Tracking payload URL pattern**:
  - `https://wsr.nhle.com/sprites/{SEASON_SLUG}/{GAME_ID}/ev{EVENT_ID}.json`
  - Example:
    - `https://wsr.nhle.com/sprites/20252026/2025020501/ev544.json`

---

### Fetching: how to reliably download `evNNN.json`
Plain navigation / naive fetches may get blocked by Cloudflare, but downloads succeed when you present the request like it’s coming from NHL.com.

#### Minimal headers that mattered in practice
- `Origin: https://www.nhl.com`
- `Referer: https://www.nhl.com/gamecenter/...` (a Gamecenter URL)
- A plausible `User-Agent`
- “Fetch metadata” headers help mimic browser CORS requests:
  - `Sec-Fetch-Site`, `Sec-Fetch-Mode`, `Sec-Fetch-Dest`

#### Observed response characteristics (informational)
- Response often includes `access-control-allow-origin: https://www.nhl.com`
- Served behind Cloudflare

---

### Payload schema: what’s inside `evNNN.json`
For the files we inspected (same game, multiple events), the payload shape was consistent:

- **Top-level**: JSON **array** of frames
- **Each frame**:
  - `timeStamp` (integer)
  - `onIce` (object / map)
    - keys: entity ids (stringified or numeric-like keys)
    - values: entity objects

#### Entity object fields (observed)
Each entity is shaped like:

- `id`
- `playerId`
- `x`, `y` (float coordinates in a rink coordinate system)
- `sweaterNumber`
- `teamId`
- `teamAbbrev`

#### Puck representation (critical for rendering)
There is no separate “puck” field in the frame objects (in the inspected events).
Instead, the puck appears as an entity in `onIce` where:

- `playerId` is `""` or `null`
- `teamAbbrev` is `""` or `null`

This is the detection logic used by `script/edge_replay_poc.rb`.

---

### Repo implementation: `script/edge_replay_poc.rb`
`script/edge_replay_poc.rb` is a proof-of-concept that turns `evNNN.json` into a short MP4 “top-down rink replay.”

#### High-level pipeline
1. **Input acquisition**
   - Use `--input` if it exists, otherwise:
   - Fetch from `wsr.nhle.com` when `--game-id` and `--event` are provided.
2. **Frame rendering**
   - Default renderer: **ImageMagick** (no Chrome needed)
   - Optional renderer: headless Chrome canvas snapshotting (kept as a fallback/reference)
3. **Encoding**
   - Uses `ffmpeg` to encode PNG frames to H.264 MP4.

#### Architecture (conceptual)
```
          ┌─────────────────────────────────────────────────┐
          │  wsr.nhle.com sprites payload (ev{event}.json)   │
          └───────────────┬─────────────────────────────────┘
                          │  (HTTP GET w/ NHL.com-like headers)
                          v
┌──────────────────────────────────────────────────────────────────┐
│ script/edge_replay_poc.rb                                         │
│  - parses frames[]                                                │
│  - for each frame: draws rink background + entities (puck+players) │
│  - expands frames to approximate real-time using timeStamp deltas  │
└───────────────┬──────────────────────────────────────────────────┘
                │ PNG sequence
                v
         ┌───────────────┐
         │    ffmpeg      │
         └───────┬───────┘
                 v
            output .mp4
```

---

### Dependencies
The script requires these external tools:
- **rsvg-convert** (from librsvg) - for SVG to PNG conversion
  - Install on macOS: `brew install librsvg`
  - Install on Linux: `apt-get install librsvg2-bin` or `yum install librsvg2-tools`
- **ImageMagick** (magick command) - for image compositing and frame rendering
  - Install on macOS: `brew install imagemagick`
- **ffmpeg** - for encoding PNG frames to MP4
  - Install on macOS: `brew install ffmpeg`

### How to run (recommended)
All Ruby commands should be run via interactive zsh so rbenv/bundler are correct:

#### Fetch + render in one step (recommended)
```bash
zsh -i -c "bundle exec ruby script/edge_replay_poc.rb --game-id 2025020501 --event 544 --out tmp/edge/ev544_poc.mp4"
```

#### Render from an already-downloaded JSON file
```bash
zsh -i -c "bundle exec ruby script/edge_replay_poc.rb --input tmp/edge/ev544.json --out tmp/edge/ev544_poc.mp4"
```

---

### Script options (high-signal)
- **Input / fetch**
  - `--input PATH`: local `evNNN.json` file
  - `--game-id ID`: e.g. `2025020501`
  - `--event N`: event id, e.g. `544`
  - `--season SLUG`: e.g. `20252026` (defaults to `YYYYYYYY+1` derived from `--game-id`)
  - `--game-url URL`: overrides the `Referer` header used during fetch
  - `--user-agent UA`: overrides UA used during fetch
- **Video / render**
  - `--out PATH`: output mp4 path
  - `--renderer imagemagick|chrome`
  - `--fps N`
  - `--speed X`
  - `--tick-seconds X` (EDGE ticks appear to be ~0.1s)
  - `--width N`, `--height N`
  - `--start N`, `--frames N` (clip range)
  - `--rink-w N`, `--rink-h N` (coordinate mapping)

---

### Rink background rendering
The script uses `Icehockeylayout.svg` as the rink background template, which provides:
- Regulation NHL rink dimensions (200' x 85')
- Accurate positioning of all lines, circles, and markings
- Faceoff circles with hash marks
- Goal creases and nets
- Trapezoid areas behind goals

The SVG is converted to PNG using `rsvg-convert` (part of librsvg) which handles complex SVG features better than ImageMagick. The converted PNG is then composited onto the canvas with proper scaling to match the EDGE coordinate system (2400 x 1020 units = 12 units/foot).

### Known limitations / TODO ideas
- **Team colors** are currently hardcoded for only a couple teams in `TEAM_COLORS`.
- **Robustness**: if the payload schema varies by season/game/event, we may need more flexible parsing.
- **Productionization**: this is a PoC; if we integrate into the bot, we'll want:
  - better caching of downloaded `evNNN.json`
  - retries / backoff for fetches
  - better logging + error reporting
  - a clean interface from "goal event id" → "download/render/post"
  - dynamic team colors from API data



# NHL EDGE API Content Guide

## Overview

This document outlines the NHL EDGE statistics API endpoints, the data they provide, and content ideas for Rod The Bot. All endpoints use the base URL `https://api-web.nhle.com/v1/edge/`.

**Important:** Always verify players are on the active roster using `NhlApi.roster('CAR')` before posting about them. Players on IR, scratched, or traded will still appear in EDGE data but should not be featured.

---

## Team EDGE Endpoints

### 1. Team Zone Time Details

**Endpoint:** `v1/edge/team-zone-time-details/{teamId}/now`

**Data Returned:**
```ruby
{
  zoneTimeDetails: [
    {
      strengthCode: "all",  # or "es", "pp", "pk"
      offensiveZonePctg: 0.4556,
      offensiveZoneRank: 1,
      offensiveZoneLeagueAvg: 0.4108,
      neutralZonePctg: 0.1837,
      neutralZoneRank: 5,
      neutralZoneLeagueAvg: 0.1783,
      defensiveZonePctg: 0.3608,
      defensiveZoneRank: 1,
      defensiveZoneLeagueAvg: 0.4108
    }
    # Repeated for es, pp, pk
  ],
  shotDifferential: {
    shotAttemptDifferential: 7.675,
    shotAttemptDifferentialRank: 2,
    sogDifferential: 0.356,
    sogDifferentialRank: 1
  }
}
```

**Content Ideas:**

1. **"By The Numbers" Pre-Game Post**
   - Team zone control dominance
   - Shot differential advantage
   - Special teams zone time (aggressive PK, etc.)

2. **Matchup Advantage Post**
   - Compare Canes zone time vs opponent
   - Highlight rankings to show superiority
   - Build pre-game hype

3. **Weekly Identity Post**
   - "This is how the Canes play"
   - Zone control metrics that define team style
   - Good for off-days/rest days

**Example Post:**
```
⚡ BY THE NUMBERS ⚡

Hurricanes zone control heading into tonight:
• 45.6% offensive zone time (#1 in NHL)
• 36.1% defensive zone time (#1 least)
• +7.7 shot differential per game (#2)

They're going to dominate possession tonight.
#LetsGoCanes
```

---

### 2. Team Skating Speed Detail

**Endpoint:** `v1/edge/team-skating-speed-detail/{teamId}/{season}/{gameType}`

**Data Returned:**
```ruby
{
  topSkatingSpeeds: [
    {
      player: { id, firstName, lastName },
      skatingSpeed: { imperial: 23.38, metric: 37.63 },
      gameDate: "2025-12-19",
      periodDescriptor: { number: 4, periodType: "OT" },
      timeInPeriod: "00:18",
      # ... game details
    }
    # Top 10 fastest speeds by team players
  ],
  skatingSpeedDetails: [
    {
      positionCode: "all",  # or "F", "D"
      maxSkatingSpeed: { imperial: 23.38, rank: 22, leagueAvg: 23.49 },
      burstsOver22: { value: 53, rank: 8, leagueAvg: 43.22 },
      bursts20To22: { value: 900, rank: 10, leagueAvg: 833.44 },
      bursts18To20: { value: 3852, rank: 16, leagueAvg: 3859.41 }
    }
    # Breakdown by position
  ]
}
```

**Content Ideas:**

1. **Speed Preview Post**
   - Team speed rankings
   - Burst counts to show sustained speed
   - "Fast team" identity validation

2. **Speed Demon Leaderboard**
   - Top 3 fastest players on team
   - Fun, competitive content
   - Good for weekly recurring post

3. **Position Group Spotlight**
   - Highlight fast defensive corps
   - Or speedy forward group
   - Show depth of speed

**Example Post:**
```
💨 CANES SPEED PREVIEW

Team speed rankings this season:
• 53 bursts over 22 mph (#8 in NHL)
• 900 bursts 20-22 mph (#10)

Fastest recorded: Seth Jarvis at 23.38 mph

They'll be flying tonight.
#TakeWarning
```

---

### 3. Team Shot Speed Detail

**Endpoint:** `v1/edge/team-shot-speed-detail/{teamId}/{season}/{gameType}`

**Data Returned:**
```ruby
{
  hardestShots: [
    {
      player: { id, firstName, lastName },
      shotSpeed: { imperial: 98.97, metric: 159.28 },
      gameDate: "2025-10-14",
      # ... game details
    }
    # Top 10 hardest shots
  ],
  shotSpeedDetails: [
    {
      position: "all",  # or "F", "D"
      topShotSpeed: { imperial: 98.97, rank: 13, leagueAvg: 97.90 },
      avgShotSpeed: { imperial: 59.64, rank: 5, leagueAvg: 58.30 },
      shotAttemptsOver100: 0,
      shotAttempts90To100: 31,
      shotAttempts80To90: 254,
      shotAttempts70To80: 713
    }
    # Breakdown by position
  ]
}
```

**Content Ideas:**

1. **Offensive Firepower Post**
   - Average shot speed ranking (Canes are top-5!)
   - Hard shot counts
   - "Heavy shots" narrative

2. **D-Corps Spotlight**
   - Defensemen shot speed
   - "Bombs from the point"
   - Highlight offensive defensemen

3. **Matchup: Shooting Power**
   - Compare team avg shot speed vs opponent
   - Shot attempt distributions
   - Goalie challenge preview

**Example Post:**
```
🎯 OFFENSIVE PREVIEW

Canes shot speed this season:
• Avg: 59.6 mph (#5 in NHL)
• Hardest: Alexander Nikishin at 98.97 mph
• 254 shots between 80-90 mph

Heavy, hard, constant pressure.
[Opponent] goalie is in for a long night.
```

---

## Skater EDGE Endpoints

All skater endpoints take `{playerId}` and have `/now` versions for current season.

### 1. Skater Detail

**Endpoint:** `v1/edge/skater-detail/{playerId}/now`

**Data Returned:**
```ruby
{
  player: {
    id, firstName, lastName, position, sweaterNumber,
    headshot, goals, assists, points, gamesPlayed, team
  },
  seasonsWithEdgeStats: [ { id: 20252026, gameTypes: [2] } ],
  topShotSpeed: {
    imperial: 84.34,
    metric: 135.73,
    percentile: 0.5378,
    leagueAvg: { imperial: 82.93 },
    overlay: { # Game context when it happened }
  },
  # Plus skating speed summary
}
```

**Content Ideas:**
- Quick player overview with one standout EDGE metric
- Combined with other data for "complete player" posts

---

### 2. Skater Zone Time

**Endpoint:** `v1/edge/skater-zone-time/{playerId}/now`

**Data Returned:**
```ruby
{
  zoneTimeDetails: [
    {
      strengthCode: "all",  # or "es", "pp", "pk"
      offensiveZonePctg: 0.4825,
      offensiveZonePercentile: 0.9928,  # 99th percentile!
      offensiveZoneLeagueAvg: 0.4241,
      neutralZonePctg: 0.1753,
      neutralZonePercentile: 0.3382,
      defensiveZonePctg: 0.3421,
      defensiveZonePercentile: 0.9928,
      defensiveZoneLeagueAvg: 0.3979
    }
    # Breakdown by situation
  ],
  zoneStarts: {
    offensiveZoneStartsPctg: 0.4928,
    offensiveZoneStartsPctgPercentile: 0.9978,  # Elite deployment!
    neutralZoneStartsPctg: 0.2454,
    defensiveZoneStartsPctg: 0.2720
  }
}
```

**Content Ideas:**

1. **Elite Zone Control Spotlight**
   - Highlight 99th percentile players
   - Show offensive zone dominance
   - "Controlling the game" narrative

2. **Deployment Analysis**
   - Zone start percentages
   - Show coaching trust
   - Offensive vs defensive role

3. **Complete Player Profile**
   - Beyond goals/assists
   - Zone time shows impact
   - Two-way play appreciation

4. **Special Teams Analysis**
   - PK zone time (aggressive PKers)
   - PP zone time (offensive pressure)
   - Unique roles

**Example Post:**
```
🔍 EDGE SPOTLIGHT: Sebastian Aho

Beyond his 40 points, Aho controls the ice:

• 48.3% time in offensive zone (99th percentile!)
• 34.2% time in defensive zone (99th percentile)
• 49.3% offensive zone starts (99.8th percentile)

He's not just scoring. He's dominating.
#TakeWarning
```

---

### 3. Skater Shot Location Detail

**Endpoint:** `v1/edge/skater-shot-location-detail/{playerId}/now`

**Data Returned:**
```ruby
{
  shotLocationDetails: [
    {
      area: "L Circle",  # 17 different zones
      sog: 17,
      goals: 3,
      shootingPctg: 0.1765,
      sogPercentile: 0.9653,
      goalsPercentile: 0.9562,
      shootingPctgPercentile: 0.7993
    }
    # For all ice areas: Behind Net, Crease, High Slot, Low Slot,
    # L/R Circles, L/R Corners, L/R Net Side, L/R Points,
    # Outside L/R, Center Point, Offensive Neutral Zone, Beyond Red Line
  ]
}
```

**Content Ideas:**

1. **Hot Zones Preview**
   - Show where player scores from
   - Percentile ranks for credibility
   - "Watch for him here" predictive content

2. **Shot Chart Visualization** (future)
   - Could generate visual heat map
   - Most dangerous areas highlighted
   - Educational for fans

3. **Matchup: Scorer vs Goalie**
   - Player's hot zones vs goalie's weak zones
   - Strategic preview
   - "Exploit this mismatch" content

4. **Shooting Efficiency Post**
   - High shooting percentage areas
   - Elite finishing zones
   - Quality over quantity narrative

**Example Post:**
```
🎯 AHO'S DANGER ZONES

Watch for Sebastian Aho in these areas tonight:

• Left Circle: 17 SOG, 3G (96th percentile)
• High Slot: 15 SOG, 3G (96th percentile)
• Left Point: 4 SOG, 1G (95th percentile)

He's lethal from the left side.
#LetsGoCanes
```

---

### 4. Skater Skating Speed Detail

**Endpoint:** `v1/edge/skater-skating-speed-detail/{playerId}/now`

**Data Returned:**
```ruby
{
  topSkatingSpeeds: [
    {
      skatingSpeed: { imperial: 22.18, metric: 35.70 },
      gameDate: "2025-11-08",
      periodDescriptor: { number: 1, periodType: "REG" },
      timeInPeriod: "17:40",
      # ... game details
    }
    # Top 10 speeds for this player
  ],
  skatingSpeedDetails: {
    maxSkatingSpeed: {
      imperial: 22.18,
      percentile: 0.5474,
      leagueAvg: { imperial: 22.02 }
    },
    burstsOver22: { value: 1, percentile: 0.4562, leagueAvg: 2.13 },
    bursts20To22: { value: 74, percentile: 0.8485, leagueAvg: 39.76 },
    bursts18To20: { value: 255, percentile: 0.7810, leagueAvg: 172.86 }
  }
}
```

**Content Ideas:**

1. **Speed Demon Profile**
   - Highlight fastest players
   - Percentile rankings
   - "Fastest on the team" content

2. **Speed Burst Analysis**
   - Show sustained speed (20-22 mph bursts)
   - Not just top speed, but consistency
   - "Always moving" narrative

3. **Speed + Production Correlation**
   - Fast players who score
   - Speed creating chances
   - "Can't catch him" content

**Example Post:**
```
💨 SPEED DEMON: Seth Jarvis

Jarvis leads the Canes in speed:
• Top speed: 23.38 mph (96th percentile)
• 8 bursts over 22 mph this season
• 80 bursts between 20-22 mph

That OT winner vs Florida? Hit 23.38 in 18 seconds.
Watch #24 fly tonight.
```

---

### 5. Skater Shot Speed Detail

**Endpoint:** `v1/edge/skater-shot-speed-detail/{playerId}/now`

**Data Returned:**
```ruby
{
  hardestShots: [
    {
      shotSpeed: { imperial: 84.34, metric: 135.73 },
      gameDate: "2025-11-23",
      periodDescriptor: { number: 2, periodType: "REG" },
      timeInPeriod: "12:41",
      # ... game details
    }
    # Top 10 hardest shots
  ],
  shotSpeedDetails: {
    topShotSpeed: { imperial: 84.34, percentile: 0.5378 },
    avgShotSpeed: { imperial: 57.46, metric: 92.47 },
    shotAttemptsOver100: 0,
    shotAttempts90To100: 0,
    shotAttempts80To90: 12,
    shotAttempts70To80: 48
  }
}
```

**Content Ideas:**

1. **Heavy Shooter Profile**
   - Hardest shot speed
   - Shot velocity leader
   - "Release" narrative

2. **Shot Volume + Speed**
   - Average shot speed
   - Hard shot counts
   - "Dangerous from anywhere" content

3. **Defenseman Spotlight**
   - D-men with bombs from the point
   - 90+ mph shots
   - PP weapon content

---

### 6. Skater Skating Distance Detail

**Endpoint:** `v1/edge/skater-skating-distance-detail/{playerId}/now`

**Data Returned:**
```ruby
{
  skatingDistanceLast10: [
    {
      gameCenterLink: "/gamecenter/...",
      gameDate: "2026-01-01",
      distanceSkatedAll: { imperial: 2.76, metric: 4.45 },
      toiAll: 1010,  # seconds
      distanceSkatedEven: { imperial: 2.39, metric: 3.84 },
      toiEven: 874,
      distanceSkatedPP: { imperial: 0.38, metric: 0.61 },
      toiPP: 136,
      distanceSkatedPK: { imperial: 0.07, metric: 0.12 },
      toiPK: 31,
      # ... team details
    }
    # Last 10 games
  ]
}
```

**Content Ideas:**

1. **Workload Watch**
   - Miles skated in recent game
   - "Workhorse" appreciation
   - High-effort recognition

2. **Trend Detection: Increased Usage**
   - TOI trending up over last 5-10 games
   - Distance skated increasing
   - "Earning more ice time" narrative

3. **Trend Detection: PP Promotion**
   - PP TOI increasing in recent games
   - Distance on PP increasing
   - "Moving up the depth chart" content

4. **Situational Usage Analysis**
   - Playing all situations (ES + PP + PK)
   - "Do-everything" player
   - Complete player profile

5. **Hot Streak Correlation**
   - High skating distance + high points
   - "Working hard, producing" narrative
   - Validate point production with effort

**Example Post:**
```
🔥 AHO IS HEATING UP

Sebastian Aho's last 4 games:
• 7G-5A = 12 points
• Averaging 3.5 miles skated per game
• 22+ minutes TOI in 3 of 4 games
• Heavy power play usage

The production AND the workload are elite.
#TakeWarning
```

---

### 7. Skater Comparison

**Endpoint:** `v1/edge/skater-comparison/{playerId}/now`

**Data Returned:**
Summary endpoint combining shot speed, skating speed, and other metrics. Similar to skater-detail but formatted for comparison views.

**Content Ideas:**
- Side-by-side player comparisons
- "Who's better?" debates with data
- Prospect vs veteran comparisons

---

## Goalie EDGE Endpoints

### 1. Goalie Detail

**Endpoint:** `v1/edge/goalie-detail/{playerId}/now`

**Data Returned:**
```ruby
{
  player: {
    id, firstName, lastName, shootsCatches, sweaterNumber,
    headshot, wins, losses, overtimeLosses,
    goalsAgainstAvg, savePctg, gamesPlayed, team
  },
  stats: {
    goalsAgainstAvg: { value: 2.33, percentile: 0.9180, leagueAvg: 2.95 },
    gamesAbove900: { value: 0.5625, percentile: 0.6721, leagueAvg: 0.5031 },
    goalDifferentialPer60: { value: 1.35, percentile: 0.9672, leagueAvg: 0.11 },
    goalSupportAvg: { value: 3.67, percentile: 0.9508, leagueAvg: 2.95 },
    pointPctg: { value: 0.8438, percentile: 0.9836, leagueAvg: 0.4799 }
  },
  shotLocationSummary: [
    {
      locationCode: "all",  # or "high", "long", "mid"
      goalsAgainst: 38,
      saves: 346,
      savePctg: 0.9010,
      # ... percentiles
    }
  ],
  shotLocationDetails: [
    {
      area: "Low Slot",
      saves: 104,
      savePctg: 0.8889,
      savePctgPercentile: 1.0000  # Elite!
    }
    # For all 17 ice areas
  ]
}
```

**Content Ideas:**

1. **Fortress Zones Post**
   - Highlight areas where goalie is elite (70th+ percentile)
   - "Low Slot lockdown" narratives
   - Build confidence in starter

2. **Advanced Goalie Metrics**
   - Goal differential per 60
   - Games above .900
   - Beyond basic save percentage

3. **Goalie Matchup Preview**
   - Compare starting goalies
   - Zone-by-zone comparison
   - Strategic advantage analysis

4. **Consistency Tracker**
   - Games above .900 percentage
   - Point percentage for team
   - "Winning goalie" narrative

**Example Post:**
```
🥅 FORTRESS ZONES: Brandon Bussi

Bussi's elite save areas tonight:
• Low Slot: .889 SV% (100th percentile!)
• High Slot: .838 SV% (100th percentile)
• Goal Diff: +1.35/60 (97th percentile)

He's stopping shots from the most dangerous spots.
#LetsGoCanes
```

---

### 2. Goalie Shot Location Detail

**Endpoint:** `v1/edge/goalie-shot-location-detail/{playerId}/now`

More detailed version of shot location breakdown with percentiles for shots against, saves, goals against, and save percentage per area.

**Content Ideas:**
- Detailed zone-by-zone goalie analysis
- "Where opponents are scoring" scouting report
- Weakness identification (for opponent goalies)

---

### 3. Goalie Comparison

**Endpoint:** `v1/edge/goalie-comparison/{playerId}/now`

Summary comparison format for goalies.

**Content Ideas:**
- Head-to-head goalie matchup posts
- "Battle of the pipes" content
- Advantage/disadvantage analysis

---

## Content Strategy & Implementation

### Pre-Game Content Flow

**Morning (10:00 AM):**
1. Yesterday's scores (existing)
2. Today's schedule (existing)
3. Standings (existing)
4. **→ NEW: "By The Numbers" team EDGE post**
   - Team zone time + shot differential
   - Speed rankings
   - Identity validation

**Midday (12:00-2:00 PM):**
5. Stats preview (existing)
6. **→ NEW: Player EDGE spotlight (2-3x per week)**
   - Rotate through active roster players
   - Zone time for stars
   - Hot zones for scorers
   - Speed for fast players

**Late Afternoon (4:00-5:00 PM):**
7. Milestones preview (existing)
8. **→ NEW: Starting goalie fortress zones OR matchup advantage**
   - Goalie's elite zones (if announced)
   - OR zone control matchup vs opponent

### Weekly/Periodic Content

**Weekly (off-days):**
- Speed Demons Leaderboard (top 3 fastest on team)
- Workload Warriors (highest skating distance)
- Hot Streak Alert (players with 5+ points in last 3 games)
- Special Teams EDGE breakdown

**Bi-Weekly:**
- Trend Report (players heating up, increased roles)
- Team EDGE rankings update
- Position group spotlights (fast D-corps, etc.)

### Content Type Priority

**High Priority (Do First):**
1. ✅ "By The Numbers" team EDGE preview
2. ✅ Player zone time spotlight (for stars)
3. ✅ Starting goalie fortress zones

**Medium Priority (Add Later):**
4. Hot zones / shot location posts
5. Speed demon leaderboard
6. Matchup advantage comparisons

**Low Priority (Nice to Have):**
7. Skating distance workload posts
8. Shot speed posts
9. Trend detection alerts

### Important Implementation Notes

#### 1. Always Verify Active Roster

```ruby
# Get current roster
roster = NhlApi.roster('CAR')
roster_ids = roster.keys

# Only post about players in roster
if roster_ids.include?(player_id)
  # Post about player
else
  # Skip - player might be injured, scratched, or traded
end
```

#### 2. Cache EDGE Data Appropriately

```ruby
# EDGE data changes slowly (season-long stats)
Rails.cache.fetch("edge_team_zone_time_#{team_id}", expires_in: 6.hours) do
  fetch_edge_data(team_id)
end

# Player data: 6-12 hours on game days
Rails.cache.fetch("edge_player_zone_#{player_id}", expires_in: 8.hours) do
  fetch_player_edge_data(player_id)
end
```

#### 3. Handle Missing Data Gracefully

```ruby
# Not all players have all EDGE stats
# Check for nil/empty before posting
if edge_data && edge_data['zoneTimeDetails']&.any?
  # Post content
else
  # Skip this player, try next
end
```

#### 4. Percentile Thresholds for "Elite"

```ruby
# Only highlight truly elite metrics
def elite_metric?(percentile)
  percentile >= 0.90  # 90th percentile or higher
end

def above_average?(percentile)
  percentile >= 0.70  # 70th percentile or higher
end
```

#### 5. Combine with Existing Stats

```ruby
# EDGE data is most powerful when combined with traditional stats
player_stats = NhlApi.fetch_player_landing_feed(player_id)
edge_data = fetch_edge_zone_time(player_id)

# "40 points AND 99th percentile zone control"
# "2.33 GAA (92nd percentile) in 13 wins"
```

---

## API Rate Limiting & Performance

### Fetch Strategy

**On game days:**
- Fetch team EDGE data once in morning (3 endpoints)
- Fetch 2-3 featured player EDGE data (1-2 endpoints each)
- Fetch starting goalie data when lineup announced (1 endpoint)
- **Total: ~10-15 API calls per game day**

**Weekly:**
- Can fetch full roster EDGE data for trend analysis
- Cache for 24 hours

### Error Handling

```ruby
def fetch_edge_data(endpoint)
  response = HTTParty.get(endpoint)

  if response.success?
    response.parsed_response
  else
    Rails.logger.error("EDGE API error: #{response.code}")
    nil
  end
rescue => e
  Rails.logger.error("EDGE API exception: #{e.message}")
  nil
end
```

---

## Sample Worker Implementation

### EdgeTeamPreviewWorker

```ruby
# app/workers/rod_the_bot/edge_team_preview_worker.rb
module RodTheBot
  class EdgeTeamPreviewWorker
    include Sidekiq::Worker

    def perform(game_id)
      team_id = 12  # Carolina Hurricanes

      # Fetch team zone time data
      zone_data = fetch_team_zone_time(team_id)
      return unless zone_data

      # Format post text
      text = format_team_preview(zone_data)

      # Post to Bluesky
      Post.new.create_post(text: text)
    end

    private

    def fetch_team_zone_time(team_id)
      Rails.cache.fetch("edge_team_zone_#{team_id}", expires_in: 6.hours) do
        response = HTTParty.get(
          "https://api-web.nhle.com/v1/edge/team-zone-time-details/#{team_id}/now"
        )
        response.success? ? response.parsed_response : nil
      end
    end

    def format_team_preview(data)
      all_situations = data['zoneTimeDetails'].find { |d| d['strengthCode'] == 'all' }
      shot_diff = data['shotDifferential']

      oz_pct = (all_situations['offensiveZonePctg'] * 100).round(1)
      oz_rank = all_situations['offensiveZoneRank']
      dz_pct = (all_situations['defensiveZonePctg'] * 100).round(1)
      dz_rank = all_situations['defensiveZoneRank']
      shot_diff_val = shot_diff['shotAttemptDifferential'].round(1)
      shot_diff_rank = shot_diff['shotAttemptDifferentialRank']

      <<~TEXT
        ⚡ BY THE NUMBERS ⚡

        Hurricanes zone control heading into tonight:

        🏒 Zone Dominance
        • #{oz_pct}% offensive zone time (##{oz_rank} in NHL)
        • #{dz_pct}% defensive zone time (##{dz_rank} least)
        • +#{shot_diff_val} shot differential per game (##{shot_diff_rank})

        They're going to dominate possession tonight.

        #LetsGoCanes
      TEXT
    end
  end
end
```

---

## Testing EDGE Content

### A/B Testing Approach

1. **Start with "By The Numbers" team post** for 5-10 games
   - Track engagement (likes, reposts, replies)
   - Compare to average engagement on other pre-game posts

2. **Add player spotlights** if team post performs well
   - Rotate through different types (zone time, hot zones, speed)
   - Track which types get best engagement

3. **Add weekly content** if daily posts perform well
   - Speed leaderboards
   - Trend reports

### Engagement Metrics to Track

- Likes per post (compare to baseline)
- Reposts (shows fans find it shareable)
- Reply sentiment (positive, questions, discussions)
- Time investment vs. engagement (ROI)

### Content Iteration

- Drop low-engagement content types
- Double down on high-engagement types
- Adjust posting time if needed
- Refine language based on replies

---

## Future Enhancements

### Potential Additions

1. **Visual EDGE content**
   - Shot chart heat maps
   - Zone time visualizations
   - Speed comparison graphics

2. **Opponent EDGE analysis**
   - Fetch opponent team/player data
   - "Attack their weakness" strategy posts
   - Matchup advantage deep dives

3. **Historical EDGE tracking**
   - Compare to last season
   - "Best zone control since 2021" narratives
   - Playoff EDGE stats

4. **Interactive content**
   - Polls: "Who's faster: Player A or B?"
   - Guess the stat challenges
   - Fan engagement around EDGE data

---

## Quick Reference: Best Content Ideas

### Top 5 Easiest to Implement

1. **"By The Numbers" team preview** - 1 API call, always relevant
2. **Starting goalie fortress zones** - 1 API call, builds confidence
3. **Player zone time spotlight** - 1 API call, elite percentiles impressive
4. **Speed demon leaderboard** - 1 API call, fun weekly content
5. **Matchup advantage** - 2 API calls (team + opponent), builds hype

### Top 5 Most Engaging Potential

1. **Hot streak + workload correlation** - validates production with effort
2. **Player zone time spotlight** - 99th percentile stats are shocking
3. **"By The Numbers" team identity** - fans love having receipts
4. **Hot zones preview** - gives fans something to watch for
5. **Speed demon leaderboard** - competitive, highlights different players

### Top 5 Most Unique (vs Other Bots/Accounts)

1. **Zone time percentiles** - advanced metric most don't use
2. **Skating distance trends** - nobody else tracking this
3. **Fortress zones for goalies** - location-specific is rare
4. **Workload watch** - appreciation content, not results-focused
5. **Special teams zone time** - aggressive PK narrative is unique

---

## Conclusion

EDGE data provides a wealth of content opportunities that:
- Validate what fans observe ("they look fast" → here's proof)
- Educate fans on complete player value (beyond goals/assists)
- Build anticipation (fortress zones, hot zones, speed matchups)
- Appreciate effort (workload, skating distance)
- Create unique, data-driven narratives

Start with the "By The Numbers" team preview, add player spotlights gradually, and iterate based on engagement. The data is rich, accessible, and updates automatically throughout the season.

**Most importantly:** Always verify players are on the active roster before posting about them!

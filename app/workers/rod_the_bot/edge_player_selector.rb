module RodTheBot
  module EdgePlayerSelector
    # Get players who are on roster, played in recent games, and meet criteria
    def select_eligible_players(last_n_games: 5, min_games_played: 4, criteria:)
      team_id = ENV["NHL_TEAM_ID"].to_i
      team_abbrev = ENV["NHL_TEAM_ABBREVIATION"]

      # Get last N completed games
      game_ids = get_recent_game_ids(last_n_games)
      return [] if game_ids.empty?

      # Get current roster
      roster = NhlApi.roster(team_abbrev)
      roster_player_ids = roster.keys.map(&:to_i)

      # Track player stats in recent games
      player_stats = collect_player_stats(game_ids, team_id, roster_player_ids)

      # Filter by criteria
      eligible_players = []

      player_stats.each do |player_id, stats|
        next if stats[:games] < min_games_played

        if meets_criteria?(player_id, stats, criteria)
          eligible_players << {
            id: player_id,
            name: stats[:name],
            games: stats[:games],
            points: stats[:points],
            goals: stats[:goals]
          }
        end
      end

      eligible_players
    end

    private

    def get_recent_game_ids(last_n)
      team_abbrev = ENV["NHL_TEAM_ABBREVIATION"]
      recent_games = []
      days_back = 0

      # Walk backwards through schedule to find completed games
      while recent_games.length < last_n && days_back < 30
        date = (Date.today - days_back.days).strftime("%Y-%m-%d")
        schedule = NhlApi.fetch_team_schedule(date: date)

        if schedule && schedule["games"]
          completed = schedule["games"].select { |g| g["gameState"] == "OFF" || g["gameState"] == "FINAL" }
          recent_games.concat(completed)
        end

        days_back += 7
      end

      recent_games.uniq { |g| g["id"] }.last(last_n).map { |g| g["id"] }
    end

    def collect_player_stats(game_ids, team_id, roster_player_ids)
      player_stats = Hash.new { |h, k| h[k] = {games: 0, points: 0, goals: 0, name: nil} }

      game_ids.each do |game_id|
        boxscore = NhlApi.fetch_boxscore_feed(game_id)
        players = get_players_from_boxscore(boxscore, team_id)

        players.each do |player|
          player_id = player["playerId"]
          next unless roster_player_ids.include?(player_id)

          player_stats[player_id][:games] += 1
          player_stats[player_id][:points] += (player["points"] || 0)
          player_stats[player_id][:goals] += (player["goals"] || 0)
          player_stats[player_id][:name] ||= player.dig("name", "default")
        end
      end

      player_stats
    end

    def get_players_from_boxscore(boxscore, team_id)
      home_id = boxscore.dig("homeTeam", "id")
      team_key = (home_id == team_id) ? "homeTeam" : "awayTeam"

      players = []
      ["forwards", "defense"].each do |position_group|
        group_players = boxscore.dig("playerByGameStats", team_key, position_group) || []
        players.concat(group_players)
      end

      players
    end

    def meets_criteria?(player_id, stats, criteria)
      case criteria
      when :zone_control_elite
        return false if stats[:points] < 3

        edge_data = NhlApi.fetch_skater_zone_time(player_id)
        return false unless edge_data && edge_data["zoneTimeDetails"]

        all_situations = edge_data["zoneTimeDetails"].find { |d| d["strengthCode"] == "all" }
        return false unless all_situations

        oz_percentile = (all_situations["offensiveZonePercentile"] || 0) * 100
        dz_percentile = (all_situations["defensiveZonePercentile"] || 0) * 100
        oz_starts_percentile = (edge_data.dig("zoneStarts", "offensiveZoneStartsPctgPercentile") || 0) * 100

        oz_percentile >= 85 || dz_percentile >= 85 || oz_starts_percentile >= 85

      when :hot_zones
        return false if stats[:goals] < 3

        shot_location_data = NhlApi.fetch_skater_shot_location_detail(player_id)
        return false unless shot_location_data && shot_location_data["shotLocationDetails"]

        elite_zones = shot_location_data["shotLocationDetails"].select do |zone|
          (zone["goalsPercentile"] || 0) >= 0.80
        end

        elite_zones.count >= 2

      when :high_workload
        return false if stats[:points] < 5

        distance_data = NhlApi.fetch_skater_skating_distance_detail(player_id)
        return false unless distance_data && distance_data["skatingDistanceLast10"]

        # Get average distance from recent games
        recent_games = distance_data["skatingDistanceLast10"].first(3)
        return false if recent_games.length < 3

        avg_distance = recent_games.sum { |g| g.dig("distanceSkatedAll", "imperial") || 0 } / recent_games.length.to_f
        avg_distance >= 2.5

      else
        false
      end
    end
  end
end


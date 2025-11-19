module RodTheBot
  class PlayerStreaksWorker
    include Sidekiq::Worker
    include RodTheBot::PlayerFormatter
    include ActionView::Helpers::TextHelper

    def perform
      # Skip preseason - stats don't count
      return if NhlApi.preseason?

      team_id = ENV["NHL_TEAM_ID"].to_i
      season_type = NhlApi.postseason? ? "Playoffs" : "Regular Season"

      # Get currently rostered players
      current_roster = get_current_roster_player_ids
      return if current_roster.empty?

      # Get active player streaks
      streaks = analyze_player_streaks(team_id, current_roster)
      return if streaks.empty?

      # Post streaks as a separate thread
      post_streaks_in_thread(streaks, season_type)
    end

    private

    def get_current_roster_player_ids
      # Get current team roster
      roster = NhlApi.roster(ENV["NHL_TEAM_ABBREVIATION"])
      roster.keys.map(&:to_s)
    end

    def analyze_player_streaks(team_id, current_roster)
      streaks = []
      min_streak_length = (ENV["STREAK_MIN_LENGTH"] || "3").to_i

      # Check all players on the roster
      current_roster.each do |player_id|
        player_type = get_player_type(player_id)

        if player_type == "goalie"
          # Check goalie win streaks
          recent_games = get_goalie_recent_games(player_id)
          next if recent_games.empty?

          win_streak = calculate_goalie_win_streak(recent_games)

          if win_streak[:length] >= min_streak_length
            streaks << format_streak_data(player_id, "Wins", win_streak)
          end
        else
          # Check skater streaks
          recent_games = get_player_recent_games(player_id)
          next if recent_games.empty?

          # Analyze different streak types
          point_streak = calculate_streak(recent_games, "points")
          goal_streak = calculate_streak(recent_games, "goals")
          assist_streak = calculate_streak(recent_games, "assists")

          # Only include significant streaks (3+ games)
          if point_streak[:length] >= min_streak_length
            streaks << format_streak_data(player_id, "Points", point_streak)
          end
          if goal_streak[:length] >= min_streak_length
            streaks << format_streak_data(player_id, "Goals", goal_streak)
          end
          if assist_streak[:length] >= min_streak_length
            streaks << format_streak_data(player_id, "Assists", assist_streak)
          end
        end
      end

      streaks
    end

    def get_player_recent_games(player_id)
      all_games = NhlApi.get_player_game_log(player_id, 20) # Get more games to filter
      filter_games_by_season_type(all_games)
    end

    def get_goalie_recent_games(player_id)
      all_games = NhlApi.get_goalie_game_log(player_id, 20) # Get more games to filter
      filter_games_by_season_type(all_games)
    end

    def filter_games_by_season_type(games)
      # api-web endpoint already scopes to season/type; just ensure we take recent entries
      # If these fields exist (when using stats REST), keep compatibility
      current_season = NhlApi.current_season
      target_game_type = NhlApi.postseason? ? 3 : 2 # 2 = regular season, 3 = playoffs

      filtered = if games.first&.key?("seasonId") || games.first&.key?("gameTypeId")
        games.select do |game|
          game["seasonId"].to_s == current_season &&
            game["gameTypeId"].to_i == target_game_type
        end
      else
        games
      end

      filtered.first(10)
    end

    def get_player_type(player_id)
      roster = NhlApi.roster(ENV["NHL_TEAM_ABBREVIATION"])
      player = roster[player_id.to_i]
      return "goalie" if player && player[:position] == "G"
      "skater"
    end

    def calculate_streak(games, stat_type)
      streak_length = 0
      streak_games = []

      # Iterate from most recent to older games to capture the active streak
      games.each do |game|
        if game[stat_type].to_i > 0
          streak_length += 1
          streak_games << game
        else
          break
        end
      end

      {
        length: streak_length,
        games: streak_games.reverse,
        total_stats: streak_games.sum { |g| g[stat_type].to_i }
      }
    end

    def calculate_goalie_win_streak(games)
      streak_length = 0
      streak_games = []

      # Iterate from most recent to older games to capture the active win streak
      games.each do |game|
        # First, check if the goalie actually played (was the goaltender of record)
        # A goalie played if they have a decision (W/L/OTL) or if any of wins/losses/otLosses > 0
        decision = game["decision"].to_s.upcase
        wins = game["wins"].to_i
        losses = game["losses"].to_i
        ot_losses = (game["otLosses"] || game["otl"] || 0).to_i

        goalie_played = %w[W L OTL].include?(decision) ||
          wins > 0 || losses > 0 || ot_losses > 0

        # Skip games where the goalie didn't play (don't break the streak)
        next unless goalie_played

        # If they played and won, continue the streak
        if wins > 0 || decision == "W"
          streak_length += 1
          streak_games << game
        else
          # If they played and lost/OTL, break the streak
          break
        end
      end

      {
        length: streak_length,
        games: streak_games.reverse,
        total_stats: streak_games.sum { |g| g["wins"].to_i }
      }
    end

    def format_streak_data(player_id, streak_type, streak_data)
      player_name = get_player_name_from_id(player_id)
      {
        player_name: player_name,
        streak_type: streak_type,
        length: streak_data[:length],
        total_stats: streak_data[:total_stats]
      }
    end

    def get_player_name_from_id(player_id)
      # Use existing roster data if available
      roster = NhlApi.roster(ENV["NHL_TEAM_ABBREVIATION"])
      player = roster[player_id.to_i]
      if player
        return format_player_with_components(player[:sweaterNumber], player[:firstName], player[:lastName])
      end

      # Fallback to API call
      player_data = NhlApi.fetch_player_landing_feed(player_id)
      format_player_name(player_data)
    end

    def post_streaks_in_thread(streaks, season_type)
      return if streaks.empty?

      # Sort by streak length (longest first)
      streaks.sort_by! { |s| -s[:length] }

      # Generate unique keys for threading
      current_date = Time.now.strftime("%Y%m%d")
      base_key = "player_streaks:#{current_date}"

      # Split streaks into chunks that fit within character limit
      streak_chunks = split_streaks_into_chunks(streaks, season_type)

      return if streak_chunks.empty?

      # Post first chunk as main post
      first_chunk = streak_chunks.first
      first_key = "#{base_key}:1"
      RodTheBot::Post.perform_async(first_chunk, first_key)

      # Post remaining chunks as replies
      streak_chunks.drop(1).each_with_index do |chunk, index|
        chunk_key = "#{base_key}:#{index + 2}"
        parent_key = (index == 0) ? first_key : "#{base_key}:#{index + 1}"
        RodTheBot::Post.perform_in((index + 1).seconds, chunk, chunk_key, parent_key)
      end
    end

    def split_streaks_into_chunks(streaks, season_type)
      chunks = []
      current_chunk = []

      # Account for team hashtags that will be added by Post worker
      hashtags = ENV["TEAM_HASHTAGS"] || ""
      hashtag_length = hashtags.empty? ? 0 : hashtags.length + 1 # +1 for newline
      max_content_length = 300 - hashtag_length

      # Header for first chunk
      header = if season_type == "Playoffs"
        "🔥 Active Streaks (#{season_type}):\n\n"
      else
        "🔥 Active Streaks:\n\n"
      end
      current_chunk_size = header.length
      current_chunk << header

      streaks.each do |streak|
        streak_line = format_streak_line(streak)
        line_length = streak_line.length # Already includes newline

        # If adding this streak would exceed the limit, start a new chunk
        if current_chunk_size + line_length > max_content_length && !current_chunk.empty?
          # Finish current chunk
          chunks << current_chunk.join

          # Start new chunk
          current_chunk = []
          current_chunk_size = 0
        end

        current_chunk << streak_line
        current_chunk_size += line_length
      end

      # Add final chunk if it has content
      if !current_chunk.empty?
        chunks << current_chunk.join
      end

      chunks
    end

    def format_streak_line(streak)
      "#{streak[:player_name]}: #{streak[:length]}-game #{streak[:streak_type].downcase} streak (#{streak[:total_stats]} total)\n"
    end
  end
end

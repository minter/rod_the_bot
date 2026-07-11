module RodTheBot
  class EdgeTeamShotSpeedWorker
    include Sidekiq::Worker
    include PlayerImageHelper

    def perform(game_id = nil)
      return if Nhl::SeasonCalendar.preseason?

      team_id = ENV["NHL_TEAM_ID"].to_i
      shot_data = Nhl::EdgeClient.fetch_team_shot_speed_detail(team_id)
      return unless shot_data && shot_data["shotSpeedDetails"]&.any?

      our_team_abbrev, opponent_team_abbrev, opponent_shot_data = fetch_opponent_data(game_id, team_id)

      # Filter hardest shots to only players currently on each roster
      our_abbrev = our_team_abbrev || ENV["NHL_TEAM_ABBREVIATION"]
      shot_data = filter_to_active_players(shot_data, "hardestShots", our_abbrev)
      opponent_shot_data = filter_to_active_players(opponent_shot_data, "hardestShots", opponent_team_abbrev)

      # Get player IDs for headshots
      player_ids = []
      player_ids << shot_data.dig("hardestShots", 0, "player", "id") if shot_data.dig("hardestShots", 0, "player")
      player_ids << opponent_shot_data.dig("hardestShots", 0, "player", "id") if opponent_shot_data&.dig("hardestShots", 0, "player")

      headshots = fetch_player_headshots(player_ids)

      post_text = format_team_shot_speed_post(shot_data, opponent_shot_data, our_team_abbrev, opponent_team_abbrev)
      RodTheBot::Post.perform_async(post_text, nil, nil, nil, headshots) if post_text
    rescue => e
      Rails.logger.error("EdgeTeamShotSpeedWorker error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end

    private

    def fetch_opponent_data(game_id, team_id)
      matchup = GameMatchup.for(game_id, team_id: team_id)
      return [nil, nil, nil] unless matchup

      [matchup.our_abbrev, matchup.opponent_abbrev, Nhl::EdgeClient.fetch_team_shot_speed_detail(matchup.opponent_team_id)]
    end

    def filter_to_active_players(data, players_key, team_abbrev)
      ActiveRosterFilter.call(data, players_key: players_key, team_abbrev: team_abbrev)
    end

    def format_team_shot_speed_post(data, opponent_data, our_team_abbrev, opponent_team_abbrev)
      all_positions = data["shotSpeedDetails"]&.find { |d| d["position"] == "all" }
      return nil unless all_positions

      our_team_abbrev ||= ENV["NHL_TEAM_ABBREVIATION"]

      post = "🎯 SHOT SPEED PREVIEW\n\n"
      post += format_team_shot_stats(data, all_positions, our_team_abbrev)

      if opponent_data && opponent_team_abbrev
        opponent_positions = opponent_data["shotSpeedDetails"]&.find { |d| d["position"] == "all" }
        post += "\n#{format_team_shot_stats(opponent_data, opponent_positions, opponent_team_abbrev)}" if opponent_positions
      end

      post
    end

    def format_team_shot_stats(data, all_positions, team_abbrev)
      top_shot_speed = all_positions["topShotSpeed"]
      avg_shot_speed = all_positions["avgShotSpeed"]

      return "" unless top_shot_speed && avg_shot_speed

      top_speed_val = top_shot_speed["imperial"]&.round(2)
      top_speed_rank = top_shot_speed["rank"]
      avg_speed_val = avg_shot_speed["imperial"]&.round(2)
      avg_speed_rank = avg_shot_speed["rank"]

      # Get hardest shot player name if available
      hardest_shot_player = data["hardestShots"]&.first
      player_name = if hardest_shot_player && hardest_shot_player["player"]
        player = hardest_shot_player["player"]
        Nhl::PlayerIdentity.from_landing(player, player_id: player["id"]).full_name
      end

      stats = <<~STATS
        #{team_abbrev} shot speed:
        • Average: #{avg_speed_val} mph (##{avg_speed_rank} in NHL)
        • Hardest: #{top_speed_val} mph (##{top_speed_rank})
      STATS

      if player_name
        stats += "• Hardest shot: #{player_name}\n"
      end

      stats
    end
  end
end

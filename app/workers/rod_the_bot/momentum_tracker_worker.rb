module RodTheBot
  class MomentumTrackerWorker
    include Sidekiq::Worker
    include ActionView::Helpers::TextHelper

    def perform(game_id)
      @game_id = game_id
      @feed = NhlApi.fetch_pbp_feed(game_id)
      return unless @feed

      momentum_data = analyze_game_momentum
      return if momentum_data.empty?

      post_momentum_update(momentum_data)
    end

    private

    def analyze_game_momentum
      # Get recent plays (last 10 minutes of game time)
      recent_plays = get_recent_plays
      return {} if recent_plays.empty?

      {
        shots_last_10_min: count_shots_last_10_minutes(recent_plays),
        goals_last_10_min: count_goals_last_10_minutes(recent_plays),
        penalties_last_10_min: count_penalties_last_10_minutes(recent_plays),
        momentum_shift: detect_momentum_shift(recent_plays),
        shot_differential: calculate_shot_differential(recent_plays)
      }
    end

    def get_recent_plays
      # Get plays from the last 10 minutes of game time
      # This is a simplified approach - in reality, you'd need to parse game time
      @feed["plays"].last(20) # Get last 20 plays as a proxy for recent activity
    end

    def count_shots_last_10_minutes(plays)
      plays.count { |play| play["typeCode"] == "SHOT" }
    end

    def count_goals_last_10_minutes(plays)
      plays.count { |play| play["typeCode"] == "GOAL" }
    end

    def count_penalties_last_10_minutes(plays)
      plays.count { |play| play["typeCode"] == "PENALTY" }
    end

    def calculate_shot_differential(plays)
      your_team_id = ENV["NHL_TEAM_ID"].to_i
      your_shots = plays.count { |play| play["typeCode"] == "SHOT" && play["details"]["shootingPlayerId"] && get_player_team(play["details"]["shootingPlayerId"]) == your_team_id }
      their_shots = plays.count { |play| play["typeCode"] == "SHOT" && play["details"]["shootingPlayerId"] && get_player_team(play["details"]["shootingPlayerId"]) != your_team_id }

      your_shots - their_shots
    end

    def get_player_team(player_id)
      # Get player team from roster data
      roster = NhlApi.game_rosters(@game_id)
      player = roster[player_id]
      player ? player[:team_id] : nil
    end

    def detect_momentum_shift(plays)
      # Analyze play patterns to detect momentum shifts
      recent_goals = plays.select { |play| play["typeCode"] == "GOAL" }
      recent_shots = plays.select { |play| play["typeCode"] == "SHOT" }

      if recent_goals.length >= 2
        "⚡ Scoring surge detected!"
      elsif recent_shots.length >= 5
        "🏒 Shot barrage in progress!"
      elsif recent_goals.length >= 1 && recent_shots.length >= 3
        "🔥 Momentum building!"
      end
    end

    def post_momentum_update(data)
      post_content = "🌊 Game Momentum Update:\n\n"
      post_content += "Last 10 minutes:\n"
      post_content += "• Shots: #{data[:shots_last_10_min]}\n"
      post_content += "• Goals: #{data[:goals_last_10_min]}\n"
      post_content += "• Penalties: #{data[:penalties_last_10_min]}\n"

      if data[:shot_differential] != 0
        post_content += "• Shot differential: #{"+" if data[:shot_differential] > 0}#{data[:shot_differential]}\n"
      end

      if data[:momentum_shift]
        post_content += "\n#{data[:momentum_shift]}"
      end

      RodTheBot::Post.perform_async(post_content)
    end
  end
end

module RodTheBot
  class GameStream
    include Sidekiq::Worker

    attr_reader :feed, :game_id

    def perform(game_id)
      @game_id = game_id
      @feed = NhlApi.fetch_pbp_feed(game_id)
      game_final = @feed["plays"].find { |play| play["typeDescKey"] == "game-end" }.present?

      @feed["plays"].each do |play|
        process_play(play)
      end

      if game_final
        RodTheBot::FinalScoreWorker.perform_in(60, game_id)
        RodTheBot::ThreeStarsWorker.perform_in(90, game_id)
        # Disabling due to this data not appearing to be available in the API
        # RodTheBot::ThreeMinuteRecapWorker.perform_in(600, game_id)
      else
        RodTheBot::GameStream.perform_in(30, game_id)
      end
    end

    private

    def process_play(play)
      worker_class, delay = worker_mapping[play["typeDescKey"]]
      return unless worker_class

      if REDIS.get("#{game_id}:#{play["eventId"]}").nil?
        worker_class.perform_in(delay, game_id, play)
        REDIS.set("#{game_id}:#{play["eventId"]}", "true", ex: 172800)

        # Check for milestone achievements (only during regular season and playoffs)
        check_milestone_achievements(play) unless NhlApi.preseason?
      end
    end

    def check_milestone_achievements(play)
      case play["typeDescKey"]
      when "goal"
        check_goal_milestones(play)
      end
    end

    def check_goal_milestones(play)
      return unless play["details"]["scoringPlayerId"].present?

      player_id = play["details"]["scoringPlayerId"]
      player_name = get_player_name(player_id)

      # Check if this was a milestone goal
      check_goal_milestone(player_id, player_name)
      check_point_milestone(player_id, player_name)
    end

    def get_player_name(player_id)
      # Get player name from the game feed
      player = @feed["rosterSpots"].find { |p| p["playerId"] == player_id }
      return "#{player["firstName"]["default"]} #{player["lastName"]["default"]}" if player

      # Fallback to API call
      player_feed = NhlApi.fetch_player_landing_feed(player_id)
      "#{player_feed["firstName"]["default"]} #{player_feed["lastName"]["default"]}"
    end

    def check_goal_milestone(player_id, player_name)
      career_stats = get_player_career_stats(player_id)
      goals = career_stats.dig("data", 0, "goals") || 0

      # Check for milestone goals
      milestone_goals = [1, 50, 100, 200, 300, 400, 500]

      if milestone_goals.include?(goals)
        post = format_milestone_achievement_post(player_name, "goal", goals)
        RodTheBot::Post.perform_async(post)
      end
    end

    def check_point_milestone(player_id, player_name)
      career_stats = get_player_career_stats(player_id)
      points = career_stats.dig("data", 0, "points") || 0

      # Check for milestone points
      milestone_points = [1, 50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000]

      if milestone_points.include?(points)
        post = format_milestone_achievement_post(player_name, "point", points)
        RodTheBot::Post.perform_async(post)
      end
    end

    def get_player_career_stats(player_id)
      # Cache this to avoid multiple API calls
      Rails.cache.fetch("player_career_stats_#{player_id}", expires_in: 1.hour) do
        response = HTTParty.get("https://api.nhle.com/stats/rest/en/skater/stats?cayenneExp=playerId=#{player_id}")
        response.success? ? response.parsed_response : {}
      end
    end

    def format_milestone_achievement_post(player_name, stat_type, value)
      emoji = case stat_type
      when "goal" then "🚨"
      when "point" then "🎯"
      when "win" then "🥅"
      when "shutout" then "🛡️"
      end

      # Keep it concise for Bluesky
      post = "#{emoji} MILESTONE! #{player_name} has reached #{value} career #{stat_type.pluralize(value)}! #{emoji}\n\n#{ENV["TEAM_HASHTAGS"]}"

      # Ensure we don't exceed Bluesky's character limit
      if post.length > 300
        post = "#{emoji} MILESTONE! #{player_name} reached #{value} career #{stat_type.pluralize(value)}! #{emoji}\n\n#{ENV["TEAM_HASHTAGS"]}"
      end

      post
    end

    def worker_mapping
      {
        "goal" => [RodTheBot::GoalWorker, 90],
        "penalty" => [RodTheBot::PenaltyWorker, 30],
        "period-start" => [RodTheBot::PeriodStartWorker, 1],
        "period-end" => [RodTheBot::EndOfPeriodWorker, 180]
      }
    end
  end
end

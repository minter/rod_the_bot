module RodTheBot
  class MilestoneCheckerWorker
    include Sidekiq::Worker
    include RodTheBot::PlayerFormatter

    def perform(game_id, play)
      @game_id = game_id

      case play["typeDescKey"]
      when "goal"
        check_goal_milestones(play)
      when "game-end"
        check_goalie_milestones
      end
    end

    private

    def check_goal_milestones(play)
      return unless play["details"]["scoringPlayerId"].present?

      player_id = play["details"]["scoringPlayerId"]
      player_name = get_player_name(player_id)

      # Check if this was a milestone goal
      check_goal_milestone(player_id, player_name)

      # Check assists for this goal (but not for first career milestones)
      if play["details"]["assist1PlayerId"].present?
        assist_player_id = play["details"]["assist1PlayerId"]
        assist_player_name = get_player_name(assist_player_id)
        check_assist_milestone(assist_player_id, assist_player_name)
      end

      if play["details"]["assist2PlayerId"].present?
        assist_player_id = play["details"]["assist2PlayerId"]
        assist_player_name = get_player_name(assist_player_id)
        check_assist_milestone(assist_player_id, assist_player_name)
      end
    end

    def get_player_name(player_id)
      # Get player name with jersey number from the game feed
      players = NhlApi.game_rosters(@game_id)
      format_player_from_roster(players, player_id)
    end

    def check_goal_milestone(player_id, player_name)
      career_stats = get_player_career_stats(player_id)
      goals = career_stats.dig("data", 0, "goals") || 0
      points = career_stats.dig("data", 0, "points") || 0

      # Check for milestone goals
      milestone_goals = [1, 50, 100, 200, 250, 300, 400, 500]

      if milestone_goals.include?(goals)
        post = if goals == 1
          # First career goal - check if this is also first career point
          if points == 1
            format_first_career_post(player_name, "goal")
          else
            format_milestone_achievement_post(player_name, "goal", goals)
          end
        else
          format_milestone_achievement_post(player_name, "goal", goals)
        end
        RodTheBot::Post.perform_async(post)
      end
    end

    def check_point_milestone(player_id, player_name)
      career_stats = get_player_career_stats(player_id)
      points = career_stats.dig("data", 0, "points") || 0
      goals = career_stats.dig("data", 0, "goals") || 0

      # Check for milestone points
      milestone_points = [1, 50, 100, 200, 250, 300, 400, 500, 600, 700, 750, 800, 900, 1000]

      if milestone_points.include?(points)
        if points == 1
          # First career point - check if this is also first career goal
          if goals == 1
            # Skip - first goal post will handle this
            return
          else
            post = format_first_career_post(player_name, "point")
          end
        else
          post = format_milestone_achievement_post(player_name, "point", points)
        end
        RodTheBot::Post.perform_async(post)
      end
    end

    def check_assist_milestone(player_id, player_name)
      career_stats = get_player_career_stats(player_id)
      assists = career_stats.dig("data", 0, "assists") || 0

      # Check for milestone assists (skip first career assist - handled under points)
      milestone_assists = [50, 100, 200, 250, 300, 400, 500, 600, 700, 750, 800, 900, 1000]

      if milestone_assists.include?(assists)
        post = format_milestone_achievement_post(player_name, "assist", assists)
        RodTheBot::Post.perform_async(post)
      end
    end

    def check_goalie_milestones
      # Get team goalies from the game feed
      feed = NhlApi.fetch_pbp_feed(@game_id)
      team_goalies = feed["rosterSpots"].select do |player|
        player["position"] == "G" && player["teamId"] == ENV["NHL_TEAM_ID"].to_i
      end

      team_goalies.each do |goalie|
        goalie_id = goalie["playerId"]
        goalie_name = "#{goalie["firstName"]["default"]} #{goalie["lastName"]["default"]}"

        check_goalie_win_milestone(goalie_id, goalie_name)
        check_goalie_shutout_milestone(goalie_id, goalie_name)
      end
    end

    def check_goalie_win_milestone(goalie_id, goalie_name)
      career_stats = get_player_career_stats(goalie_id)
      wins = career_stats.dig("data", 0, "wins") || 0

      # Check for milestone wins
      milestone_wins = [1, 50, 100, 200, 300, 400, 500]

      if milestone_wins.include?(wins)
        post = if wins == 1
          format_first_career_post(goalie_name, "win")
        else
          format_milestone_achievement_post(goalie_name, "win", wins)
        end
        RodTheBot::Post.perform_async(post)
      end
    end

    def check_goalie_shutout_milestone(goalie_id, goalie_name)
      career_stats = get_player_career_stats(goalie_id)
      shutouts = career_stats.dig("data", 0, "so") || 0

      # Check for milestone shutouts
      milestone_shutouts = [1, 10, 20, 30, 40, 50, 100]

      if milestone_shutouts.include?(shutouts)
        post = if shutouts == 1
          format_first_career_post(goalie_name, "shutout")
        else
          format_milestone_achievement_post(goalie_name, "shutout", shutouts)
        end
        RodTheBot::Post.perform_async(post)
      end
    end

    def get_player_career_stats(player_id)
      # Never use cache for milestone checks - always fetch fresh stats
      response = HTTParty.get("https://api.nhle.com/stats/rest/en/skater/stats?cayenneExp=playerId=#{player_id}")
      response.success? ? response.parsed_response : {}
    end

    def format_milestone_achievement_post(player_name, stat_type, value)
      emoji = case stat_type
      when "goal" then "🚨"
      when "assist" then "🍎"
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

    def format_first_career_post(player_name, stat_type)
      emoji = case stat_type
      when "goal" then "🚨"
      when "point" then "🎯"
      when "win" then "🥅"
      when "shutout" then "🛡️"
      end

      # Special formatting for first career milestones
      verb = case stat_type
      when "win", "shutout" then "earned"
      else "scored"
      end

      post = "#{emoji} MILESTONE! #{player_name} has #{verb} their first career NHL #{stat_type}! #{emoji}\n\n#{ENV["TEAM_HASHTAGS"]}"

      # Ensure we don't exceed Bluesky's character limit
      if post.length > 300
        post = "#{emoji} MILESTONE! #{player_name} #{verb} their first career NHL #{stat_type}! #{emoji}\n\n#{ENV["TEAM_HASHTAGS"]}"
      end

      post
    end
  end
end


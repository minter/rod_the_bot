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
      details = play["details"]
      return unless details
      return unless details["eventOwnerTeamId"].to_i == tracked_team_id
      return unless details["scoringPlayerId"].present?
      return unless player_on_tracked_team?(details["scoringPlayerId"])

      player_id = details["scoringPlayerId"]
      player_name = get_player_name(player_id)

      # Check if this was a milestone goal
      check_goal_milestone(player_id, player_name)

      # Check assists for this goal (but not for first career milestones)
      if details["assist1PlayerId"].present? && player_on_tracked_team?(details["assist1PlayerId"])
        assist_player_id = details["assist1PlayerId"]
        assist_player_name = get_player_name(assist_player_id)
        check_assist_milestone(assist_player_id, assist_player_name)
      end

      if details["assist2PlayerId"].present? && player_on_tracked_team?(details["assist2PlayerId"])
        assist_player_id = details["assist2PlayerId"]
        assist_player_name = get_player_name(assist_player_id)
        check_assist_milestone(assist_player_id, assist_player_name)
      end
    end

    def get_player_name(player_id)
      # Get player name with jersey number from the game feed
      format_player_from_roster(game_roster, player_id)
    end

    def check_goal_milestone(player_id, player_name)
      # Calculate career totals using pre-game stats + in-game stats
      goals = calculate_career_total(player_id, "goals")
      points = calculate_career_total(player_id, "points")

      # Check for milestone goals
      if Milestones::Thresholds.include?("goal", goals)
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
      # Calculate career totals using pre-game stats + in-game stats
      points = calculate_career_total(player_id, "points")
      goals = calculate_career_total(player_id, "goals")

      # Check for milestone points
      if Milestones::Thresholds.include?("point", points)
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
      # Calculate career totals using pre-game stats + in-game stats
      assists = calculate_career_total(player_id, "assists")

      # Check for milestone assists (skip first career assist - handled under points)
      if Milestones::Thresholds.include?("assist", assists)
        post = format_milestone_achievement_post(player_name, "assist", assists)
        RodTheBot::Post.perform_async(post)
      end
    end

    def check_goalie_milestones
      # Get team goalies from the game feed (use cached feed)
      feed = game_feed
      roster_spots = feed&.dig("rosterSpots") || []
      team_goalies = roster_spots.select do |player|
        player["position"] == "G" && player["teamId"] == ENV["NHL_TEAM_ID"].to_i
      end

      team_goalies.each do |goalie|
        goalie_id = goalie["playerId"]
        first_name = goalie.dig("firstName", "default") || ""
        last_name = goalie.dig("lastName", "default") || ""
        goalie_name = "#{first_name} #{last_name}".strip

        next if goalie_name.empty? || goalie_id.nil?

        check_goalie_win_milestone(goalie_id, goalie_name)
        check_goalie_shutout_milestone(goalie_id, goalie_name)
      end
    end

    def check_goalie_win_milestone(goalie_id, goalie_name)
      # Calculate career totals using pre-game stats + in-game result
      wins = calculate_career_total(goalie_id, "wins")

      # Check for milestone wins
      if Milestones::Thresholds.include?("win", wins)
        post = if wins == 1
          format_first_career_post(goalie_name, "win")
        else
          format_milestone_achievement_post(goalie_name, "win", wins)
        end
        RodTheBot::Post.perform_async(post)
      end
    end

    def check_goalie_shutout_milestone(goalie_id, goalie_name)
      # Calculate career totals using pre-game stats + in-game result
      shutouts = calculate_career_total(goalie_id, "shutouts")

      # Check for milestone shutouts
      if Milestones::Thresholds.include?("shutout", shutouts)
        post = if shutouts == 1
          format_first_career_post(goalie_name, "shutout")
        else
          format_milestone_achievement_post(goalie_name, "shutout", shutouts)
        end
        RodTheBot::Post.perform_async(post)
      end
    end

    def calculate_career_total(player_id, stat_type)
      career_total.for(player_id, stat_type)
    end

    def game_feed
      @game_feed ||= Nhl::GameClient.play_by_play(@game_id)
    end

    def career_total
      @career_total ||= Milestones::CareerTotal.new(game_id: @game_id, feed: method(:game_feed))
    end

    def tracked_team_id
      @tracked_team_id ||= ENV["NHL_TEAM_ID"].to_i
    end

    def game_roster
      @game_roster ||= Nhl::GameInfo.roster(@game_id)
    end

    def player_on_tracked_team?(player_id)
      player = game_roster[player_id] || game_roster[player_id.to_s]
      return false unless player

      team_id = player[:team_id] || player["team_id"] || player["teamId"]
      team_id.to_i == tracked_team_id
    end

    def format_milestone_achievement_post(player_name, stat_type, value)
      emoji = case stat_type
      when "goal" then "🚨"
      when "assist" then "🍎"
      when "point" then "🎯"
      when "win" then "🥅"
      when "shutout" then "🛡️"
      end

      # Keep it concise for Bluesky (hashtags will be added by Post worker)
      post = "#{emoji} MILESTONE! #{player_name} has reached #{value} career #{stat_type.pluralize(value)}! #{emoji}"

      # Ensure we don't exceed Bluesky's character limit
      if post.length > 300
        post = "#{emoji} MILESTONE! #{player_name} reached #{value} career #{stat_type.pluralize(value)}! #{emoji}"
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

      # Special formatting for first career milestones (hashtags will be added by Post worker)
      verb = case stat_type
      when "win", "shutout" then "earned"
      else "scored"
      end

      post = "#{emoji} MILESTONE! #{player_name} has #{verb} their first career NHL #{stat_type}! #{emoji}"

      # Ensure we don't exceed Bluesky's character limit
      if post.length > 300
        post = "#{emoji} MILESTONE! #{player_name} #{verb} their first career NHL #{stat_type}! #{emoji}"
      end

      post
    end
  end
end

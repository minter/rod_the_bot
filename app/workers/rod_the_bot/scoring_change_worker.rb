module RodTheBot
  class ScoringChangeWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector
    include RodTheBot::PeriodFormatter
    include RodTheBot::PlayerFormatter

    CHALLENGE_MAPPINGS = {
      # Home team challenges
      "chlg-hm-goal-interference" => "goaltender interference challenge",
      "chlg-hm-missed-stoppage" => "missed stoppage challenge",
      "chlg-hm-off-side" => "offside challenge",

      # Visiting team challenges
      "chlg-vis-goal-interference" => "goaltender interference challenge",
      "chlg-vis-missed-stoppage" => "missed stoppage challenge",
      "chlg-vis-off-side" => "offside challenge",

      # League-initiated reviews
      "chlg-league-goal-interference" => "league review for goaltender interference",
      "chlg-league-missed-stoppage" => "league review for missed stoppage",
      "chlg-league-off-side" => "league review for offside"
    }.freeze

    def perform(game_id, play_id, original_play, redis_key)
      # Use the original redis_key as the parent_key
      parent_key = redis_key

      # Create a new unique key for this scoring change post
      scoring_key = "#{redis_key}:scoring:#{Time.now.to_i}"
      @feed = NhlApi.fetch_pbp_feed(game_id)
      @play = @feed["plays"].find { |play| play["eventId"].to_s == play_id.to_s }
      @home = @feed["homeTeam"]
      @away = @feed["awayTeam"]

      # Check if goal was overturned (completely removed from PBP)
      if @play.blank?
        return handle_overturned_goal(game_id, play_id, original_play, redis_key)
      end

      return if @play["typeDescKey"] != "goal"

      # If nothing has changed on this scoring play, exit
      original_scorers = [original_play["details"]["scoringPlayerId"], original_play["details"]["assist1PlayerId"], original_play["details"]["assist2PlayerId"]]
      new_scorers = [@play["details"]["scoringPlayerId"], @play["details"]["assist1PlayerId"], @play["details"]["assist2PlayerId"]]

      return if new_scorers == original_scorers

      players = build_players(@feed)

      scoring_team_id = players[@play["details"]["scoringPlayerId"].to_s][:team_id]
      scoring_team = (@home["id"] == scoring_team_id) ? @home : @away

      period_name = format_period_name(@play["periodDescriptor"]["number"])

      post = format_post(scoring_team, period_name, players)

      RodTheBot::Post.perform_async(post, scoring_key, parent_key, nil, goal_images(players, @play))
    end

    def build_players(feed)
      players = {}
      feed["rosterSpots"].each do |player|
        players[player["playerId"].to_s] = {
          team_id: player["teamId"],
          number: player["sweaterNumber"].to_s,
          name: "#{player["firstName"]["default"]} #{player["lastName"]["default"]}"
        }
      end
      players
    end

    def goal_images(players, play)
      images = []

      # Safely fetch headshot for scoring player
      if play["details"]["scoringPlayerId"].present?
        player_feed = NhlApi.fetch_player_landing_feed(play["details"]["scoringPlayerId"])
        images << player_feed&.dig("headshot")
      end

      # Safely fetch headshot for assist1 player
      if play["details"]["assist1PlayerId"].present?
        player_feed = NhlApi.fetch_player_landing_feed(play["details"]["assist1PlayerId"])
        images << player_feed&.dig("headshot")
      end

      # Safely fetch headshot for assist2 player
      if play["details"]["assist2PlayerId"].present?
        player_feed = NhlApi.fetch_player_landing_feed(play["details"]["assist2PlayerId"])
        images << player_feed&.dig("headshot")
      end

      images.compact # Remove any nil values
    end

    def format_post(scoring_team, period_name, players)
      post = <<~POST
        🔔 Scoring Change

        The #{scoring_team["commonName"]["default"]} goal at #{@play["timeInPeriod"]} of the #{period_name} now reads:

      POST
      
      # Format scoring player with jersey number
      scoring_player_name = format_player_from_roster(players, @play["details"]["scoringPlayerId"])
      post += "🚨 #{scoring_player_name} (#{@play["details"]["scoringPlayerTotal"]})\n"

      post += if @play["details"]["assist1PlayerId"].present?
        assist1_name = format_player_from_roster(players, @play["details"]["assist1PlayerId"])
        "🍎 #{assist1_name} (#{@play["details"]["assist1PlayerTotal"]})\n"
      else
        "🍎 Unassisted\n"
      end
      
      if @play["details"]["assist2PlayerId"].present?
        assist2_name = format_player_from_roster(players, @play["details"]["assist2PlayerId"])
        post += "🍎🍎 #{assist2_name} (#{@play["details"]["assist2PlayerTotal"]})\n"
      end

      post
    end

    private

    def handle_overturned_goal(game_id, play_id, original_play, redis_key)
      # Find challenge event near the original goal time
      challenge_event = find_challenge_near_goal(
        original_play["timeInPeriod"],
        original_play["periodDescriptor"]["number"]
      )

      return unless challenge_event

      # Get player and team data
      players = build_players(@feed)
      scorer_id = original_play["details"]["scoringPlayerId"].to_s
      scoring_team_id = original_play["details"]["eventOwnerTeamId"]
      scoring_team = (@home["id"] == scoring_team_id) ? @home : @away

      # Parse challenge details
      challenge_reason = parse_challenge_reason(challenge_event["details"]["reason"])
      challenging_team = determine_challenging_team(challenge_event["details"]["reason"])

      # Format overturn post
      scorer_name = players[scorer_id]&.dig(:name) || "Unknown Player"
      period_name = format_period_name(original_play["periodDescriptor"]["number"])

      post = format_overturn_post(
        scoring_team: scoring_team,
        scorer_name: scorer_name,
        time: original_play["timeInPeriod"],
        period_name: period_name,
        challenge_reason: challenge_reason,
        challenging_team: challenging_team
      )

      # Post as reply to original goal
      overturn_key = "#{redis_key}:overturn:#{Time.now.to_i}"
      RodTheBot::Post.perform_async(post, overturn_key, redis_key, nil, nil)

      Rails.logger.info "ScoringChangeWorker: Posted goal overturn for game #{game_id}, play #{play_id} (#{challenge_reason})"
    end

    def find_challenge_near_goal(original_goal_time, period_number)
      # Look for challenge events within 3 minutes of original goal
      goal_minutes = time_to_minutes(original_goal_time)

      @feed["plays"].find { |play|
        play["typeDescKey"] == "stoppage" &&
          play["details"] &&
          play["details"]["reason"]&.include?("chlg") &&
          play["periodDescriptor"]["number"] == period_number &&
          (time_to_minutes(play["timeInPeriod"]) - goal_minutes).abs <= 3
      }
    end

    def time_to_minutes(time_string)
      # Convert "12:17" to 12.28 minutes
      minutes, seconds = time_string.split(":").map(&:to_i)
      minutes + (seconds / 60.0)
    end

    def parse_challenge_reason(reason_code)
      # Log unknown challenge types for documentation
      unless CHALLENGE_MAPPINGS.key?(reason_code)
        Rails.logger.info "ScoringChangeWorker: New challenge reason discovered: '#{reason_code}'"
      end

      CHALLENGE_MAPPINGS[reason_code] || "video review"
    end

    def determine_challenging_team(reason_code)
      if reason_code.include?("chlg-hm")
        @home
      elsif reason_code.include?("chlg-vis")
        @away
      elsif reason_code.include?("chlg-league")
        nil # League-initiated, not team challenge
      end
    end

    def format_overturn_post(scoring_team:, scorer_name:, time:, period_name:, challenge_reason:, challenging_team:)
      team_name = scoring_team["placeName"]["default"]

      if challenging_team
        challenger_name = challenging_team["placeName"]["default"]
        <<~POST
          ❌ Goal Overturned

          The #{team_name} goal by #{scorer_name} at #{time} of the #{period_name} has been disallowed following a successful #{challenge_reason} by #{challenger_name}.
        POST
      else
        # League-initiated review
        <<~POST
          ❌ Goal Overturned

          The #{team_name} goal by #{scorer_name} at #{time} of the #{period_name} has been disallowed following a #{challenge_reason}.
        POST
      end
    end
  end
end

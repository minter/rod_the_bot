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
      # Determine parent_key: Use most recent reply if it exists, otherwise use goal post (root)
      # Threading: Goal (root) -> most recent reply -> next reply -> etc.
      last_reply_tracker_key = "#{redis_key}:last_reply_key"
      last_reply_key = REDIS.get(last_reply_tracker_key)

      # Use last reply as parent if it exists, otherwise use root (goal post)
      parent_key = last_reply_key || redis_key

      if last_reply_key
        Rails.logger.info "ScoringChangeWorker: Replying to most recent reply with key: #{parent_key}"
      else
        Rails.logger.info "ScoringChangeWorker: No previous replies, replying to goal post (root) with key: #{parent_key}"
      end

      # Create a new unique key for this scoring change post
      scoring_key = "#{redis_key}:scoring:#{Time.now.to_i}"
      @feed = Nhl::GameClient.play_by_play(game_id)
      @home = @feed["homeTeam"]
      @away = @feed["awayTeam"]
      result = ScoringChange::Detector.new(@feed).detect(play_id: play_id, original_play: original_play)
      @play = result.play

      return handle_overturned_goal(game_id, play_id, original_play, redis_key, result.challenge) if result.status == :overturned
      return unless result.status == :corrected

      players = build_players(@feed)

      scoring_team_id = players[@play["details"]["scoringPlayerId"].to_s][:team_id]
      scoring_team = (@home["id"] == scoring_team_id) ? @home : @away

      period_name = format_period_name(@play["periodDescriptor"]["number"])

      post = format_post(scoring_team, period_name, players)

      # Post as reply - Post worker will update last_reply_key after successful post
      RodTheBot::Post.perform_async(post, scoring_key, parent_key, nil, goal_images(players, @play), nil, redis_key)
    rescue Nhl::RequestError => e
      Rails.logger.error "ScoringChangeWorker: API error for game #{game_id}, play #{play_id}: #{e.message}"
    rescue => e
      Rails.logger.error "ScoringChangeWorker: Unexpected error for game #{game_id}, play #{play_id}: #{e.class} - #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
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
        player_feed = Nhl::PlayerClient.landing(play["details"]["scoringPlayerId"])
        images << player_feed&.dig("headshot")
      end

      # Safely fetch headshot for assist1 player
      if play["details"]["assist1PlayerId"].present?
        player_feed = Nhl::PlayerClient.landing(play["details"]["assist1PlayerId"])
        images << player_feed&.dig("headshot")
      end

      # Safely fetch headshot for assist2 player
      if play["details"]["assist2PlayerId"].present?
        player_feed = Nhl::PlayerClient.landing(play["details"]["assist2PlayerId"])
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

    def handle_overturned_goal(game_id, play_id, original_play, redis_key, challenge_event)
      # Determine parent_key: Use most recent reply if it exists, otherwise use goal post (root)
      # Threading: Goal (root) -> most recent reply -> next reply -> etc.
      last_reply_tracker_key = "#{redis_key}:last_reply_key"
      last_reply_key = REDIS.get(last_reply_tracker_key)

      # Use last reply as parent if it exists, otherwise use root (goal post)
      parent_key = last_reply_key || redis_key

      if last_reply_key
        Rails.logger.info "ScoringChangeWorker (overturned): Replying to most recent reply with key: #{parent_key}"
      else
        Rails.logger.info "ScoringChangeWorker (overturned): No previous replies, replying to goal post (root) with key: #{parent_key}"
      end

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

      # Post as reply to most recent reply (or goal if no replies yet)
      overturn_key = "#{redis_key}:overturn:#{Time.now.to_i}"

      # Post as reply - Post worker will update last_reply_key after successful post
      RodTheBot::Post.perform_async(post, overturn_key, parent_key, nil, nil, nil, redis_key)

      Rails.logger.info "ScoringChangeWorker: Posted goal overturn for game #{game_id}, play #{play_id} (#{challenge_reason}), replying to: #{parent_key}"
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

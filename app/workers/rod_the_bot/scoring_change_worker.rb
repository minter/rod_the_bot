module RodTheBot
  class ScoringChangeWorker
    include Sidekiq::Worker
    include WorkerErrorHandling

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

      players = Nhl::PlayerDirectory.from_game_feed(@feed)

      scoring_team_id = players.fetch(@play["details"]["scoringPlayerId"]).team_id
      scoring_team = (@home["id"] == scoring_team_id) ? @home : @away
      post = formatter.correction(play: @play, scoring_team: scoring_team, players: players)

      # Post as reply - Post worker will update last_reply_key after successful post
      RodTheBot::Post.perform_async(post, scoring_key, parent_key, nil, ScoringChange::Images.for(@play), nil, redis_key)
    rescue Nhl::RequestError => e
      retry_job(e, game_id: game_id, play_id: play_id, operation: "fetch_scoring_change")
    rescue => e
      retry_job(e, game_id: game_id, play_id: play_id, operation: "process_scoring_change")
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
      players = Nhl::PlayerDirectory.from_game_feed(@feed)
      scoring_team_id = original_play["details"]["eventOwnerTeamId"]
      scoring_team = (@home["id"] == scoring_team_id) ? @home : @away
      post = formatter.overturn(
        original_play: original_play, scoring_team: scoring_team, challenge: challenge_event,
        home: @home, away: @away, players: players
      )

      # Post as reply to most recent reply (or goal if no replies yet)
      overturn_key = "#{redis_key}:overturn:#{Time.now.to_i}"

      # Post as reply - Post worker will update last_reply_key after successful post
      RodTheBot::Post.perform_async(post, overturn_key, parent_key, nil, nil, nil, redis_key)

      Rails.logger.info "ScoringChangeWorker: Posted goal overturn for game #{game_id}, play #{play_id}, replying to: #{parent_key}"
    end

    def formatter
      @formatter ||= ScoringChange::Formatter.new
    end
  end
end

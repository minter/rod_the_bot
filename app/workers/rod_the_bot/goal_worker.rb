module RodTheBot
  class GoalWorker
    include Sidekiq::Worker

    def perform(game_id, play)
      @game_id = game_id
      @feed = Nhl::GameClient.play_by_play(game_id)
      @play_id = play["eventId"]
      @play = Nhl::GameClient.play(game_id, @play_id)

      return if @play.blank?

      # Ensure this is actually a goal play - prevent processing non-goal events
      unless @play["typeDescKey"] == "goal"
        Rails.logger.warn "GoalWorker: Play #{@play_id} for game #{game_id} is not a goal (type: #{@play["typeDescKey"]}). Skipping."
        return
      end

      # Skip goals in the shootout
      return if @play["periodDescriptor"]["periodType"] == "SO"

      home = @feed["homeTeam"]
      away = @feed["awayTeam"]
      if home["id"].to_i == ENV["NHL_TEAM_ID"].to_i
        @your_team = home
        @their_team = away
      else
        @your_team = away
        @their_team = home
      end

      players = Nhl::GameInfo.roster(game_id)

      original_play = @play.deep_dup

      if @play["details"]["scoringPlayerId"].blank?
        # Check if game is final - don't reschedule if game is over
        game_final = @feed&.dig("gameState") == "OFF" || @feed&.dig("plays")&.find { |p| p["typeDescKey"] == "game-end" }.present?

        if game_final
          Rails.logger.warn "GoalWorker: scoringPlayerId is blank for game #{game_id}, play #{@play_id}, but game is final. Giving up."
          return
        end

        # Track retry count to prevent infinite rescheduling
        retry_key = "#{game_id}:goal:retry:#{@play_id}"
        retry_count = (REDIS.get(retry_key) || "0").to_i + 1
        max_retries = 10 # 10 minutes max (10 retries * 60 seconds)

        if retry_count >= max_retries
          Rails.logger.warn "GoalWorker: scoringPlayerId is blank for game #{game_id}, play #{@play_id} after #{retry_count} retries. Giving up."
          REDIS.del(retry_key)
          return
        end

        REDIS.set(retry_key, retry_count.to_s, ex: 1800) # 30 minutes expiry
        Rails.logger.info "GoalWorker: scoringPlayerId is blank for game #{game_id}, play #{@play_id}. Retry #{retry_count}/#{max_retries}. Rescheduling in 60 seconds."
        RodTheBot::GoalWorker.perform_in(60, game_id, @play)
        return
      end

      # Clear retry count if we successfully got scoringPlayerId
      retry_key = "#{game_id}:goal:retry:#{@play_id}"
      REDIS.del(retry_key) if REDIS.exists?(retry_key)

      # Safely get scoring player data
      scoring_player_id = @play["details"]["scoringPlayerId"]
      scoring_player = players[scoring_player_id] || players[scoring_player_id.to_s] || players[scoring_player_id.to_i]

      unless scoring_player
        Rails.logger.error "GoalWorker: Player not found in roster for game #{game_id}, play #{@play_id}, scoring_player_id: #{scoring_player_id} (type: #{scoring_player_id.class}). Players hash has #{players.size} entries. Sample keys: #{players.keys.first(3).inspect}"
        return
      end

      presentation = post_builder.build(play: @play, feed: @feed, players: players)
      scoring_team = presentation.scoring_team

      redis_key = "game:#{game_id}:goal:#{@play_id}"

      # Set the completion key so GameStream knows this goal was successfully processed
      # This allows GameStream to retry if GoalWorker fails silently
      completion_key = "#{game_id}:goal:completed:#{@play_id}"

      Rails.logger.info "GoalWorker: Posting goal for game #{game_id}, play #{@play_id}, scoring_team: #{scoring_team["commonName"]["default"]} (your_team: #{scoring_team == @your_team})"
      RodTheBot::Post.perform_async(presentation.post, redis_key, nil, nil, Goal::Images.for(@play))
      RodTheBot::ScoringChangeWorker.perform_in(600, game_id, play["eventId"], original_play, redis_key)
      RodTheBot::GoalHighlightWorker.perform_in(10, game_id, play["eventId"], redis_key) if scoring_team == @your_team
      # Generate and post EDGE replay visualization (delay 1 minute to allow EDGE data to be available)
      RodTheBot::EdgeReplayWorker.perform_in(1.minute, game_id, @play_id, redis_key) unless presentation.penalty_shot

      # Mark as completed only after successfully scheduling all workers
      REDIS.set(completion_key, "true", ex: 172800)
    rescue Nhl::RequestError => e
      Rails.logger.error "GoalWorker: API error for game #{@game_id}, play #{play["eventId"]}: #{e.message}"
    rescue => e
      Rails.logger.error "GoalWorker: Unexpected error for game #{@game_id}, play #{play["eventId"]}: #{e.class} - #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
    end

    def post_builder
      @post_builder ||= Goal::PostBuilder.new
    end
  end
end

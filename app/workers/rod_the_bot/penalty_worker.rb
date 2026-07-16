module RodTheBot
  class PenaltyWorker
    include Sidekiq::Worker
    include WorkerErrorHandling

    MAX_DESC_RETRIES = 12

    def perform(game_id, play, desc_retry_count = 0)
      feed = Nhl::GameClient.play_by_play(game_id)
      return if play.blank?

      penalty = Nhl::GameClient.play(game_id, play["eventId"])
      return unless penalty
      return discard_job("missing penalty details", game_id: game_id, play_id: play["eventId"]) unless penalty["details"].is_a?(Hash)
      return discard_job("missing period descriptor", game_id: game_id, play_id: play["eventId"]) unless penalty["periodDescriptor"].is_a?(Hash)

      if penalty.dig("details", "descKey") == "minor"
        if desc_retry_count < MAX_DESC_RETRIES
          self.class.perform_in(10.seconds, game_id, play, desc_retry_count + 1)
        else
          Rails.logger.warn "PenaltyWorker: descKey still 'minor' for game #{game_id}, play #{play["eventId"]} after #{desc_retry_count} retries. Posting with generic description."
        end
        return
      end

      home = feed["homeTeam"]
      away = feed["awayTeam"]
      tracked_team_id = ENV["NHL_TEAM_ID"].to_i
      your_team, their_team = (home["id"].to_i == tracked_team_id) ? [home, away] : [away, home]
      players = Nhl::PlayerDirectory.for_game(game_id)
      main_player_id = penalty.dig("details", "committedByPlayerId") || penalty.dig("details", "servedByPlayerId")

      unless players.fetch(main_player_id)
        Rails.logger.warn "PenaltyWorker: Player #{main_player_id} not found in roster for game #{game_id}"
        return
      end

      post = post_builder.build(
        play: penalty,
        players: players,
        your_team: your_team,
        their_team: their_team,
        tracked_team_id: tracked_team_id
      )
      headshot = Nhl::PlayerClient.landing(main_player_id)&.dig("headshot")
      RodTheBot::Post.perform_async(post, nil, nil, nil, headshot ? [headshot] : [])
    rescue Nhl::RequestError => e
      retry_job(e, game_id: game_id, play_id: play&.dig("eventId"), operation: "fetch_penalty")
    rescue => e
      retry_job(e, game_id: game_id, play_id: play&.dig("eventId"), operation: "process_penalty")
    end

    def format_penalty_name(desc_key)
      post_builder.penalty_name(desc_key)
    end

    private

    def post_builder
      @post_builder ||= Penalty::PostBuilder.new
    end
  end
end

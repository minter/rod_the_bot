module RodTheBot
  # Posts an EDGE tracking thread the morning after a game. EDGE publishes per-game data in one
  # overnight batch (around 2 am Eastern), so this cannot run when the game ends.
  class EdgeGameRecapWorker
    include Sidekiq::Worker
    include WorkerErrorHandling

    # Each run recaps "yesterday", so a retry that fires days later would describe a different game.
    sidekiq_options retry: 3

    RETRY_DELAY = 30.minutes
    MAX_ATTEMPTS = 6
    CLAIM_TTL = 2.days.to_i
    PLAYED_STATES = %w[OFF FINAL].freeze
    PRESEASON = 1

    def perform(attempt = 0)
      return if Nhl::SeasonCalendar.preseason?

      game = yesterdays_game
      return unless game

      game_id = game["id"]
      team_id = ENV.fetch("NHL_TEAM_ID").to_i
      boxscore = Nhl::GameClient.boxscore(game_id)
      # The schedule may have been cached while the game was live; the boxscore is fetched fresh.
      return unless PLAYED_STATES.include?(boxscore["gameState"])

      side, opponent_side = (boxscore.dig("homeTeam", "id").to_i == team_id) ? %w[homeTeam awayTeam] : %w[awayTeam homeTeam]

      result = EdgeRecap::GameData.build(
        game_id: game_id,
        team: Nhl::EdgeClient.fetch_team_skating_distance_detail(team_id, game_id: game_id, fresh: true),
        opponent: optional(game_id, "opponent distance") do
          Nhl::EdgeClient.fetch_team_skating_distance_detail(boxscore.dig(opponent_side, "id").to_i, game_id: game_id, fresh: true)
        end,
        shots: optional(game_id, "shot speed") { Nhl::EdgeClient.fetch_team_shot_speed_detail(team_id, game_id: game_id, fresh: true) },
        speeds: optional(game_id, "skating speed") { Nhl::EdgeClient.fetch_team_skating_speed_detail(team_id, game_id: game_id, fresh: true) },
        skaters: skater_distances(game_id, boxscore.dig("playerByGameStats", side))
      )
      return wait_for_data(game_id, attempt) unless result

      directory = Nhl::PlayerDirectory.for_game(game_id)
      posts = EdgeRecap::Formatter.new(
        result: result,
        names: ->(player_id) { directory.fetch(player_id)&.name_with_number },
        team_name: boxscore.dig(side, "commonName", "default"),
        opponent_name: boxscore.dig(opponent_side, "commonName", "default"),
        home: side == "homeTeam"
      ).posts
      enqueue_once(game_id, posts)
    rescue => e
      retry_job(e, game_id: game_id, attempt: attempt, operation: "edge_game_recap")
    end

    private

    def yesterdays_game
      yesterday = Time.use_zone(ENV.fetch("TIME_ZONE")) { Time.zone.today } - 1
      game = Nhl::ScheduleClient.todays_game(date: yesterday)
      game if game && game["gameType"] != PRESEASON && game["gameScheduleState"] == "OK"
    end

    # One request per dressed skater: EDGE has no per-game listing for a whole team.
    def skater_distances(game_id, team_stats)
      player_ids = %w[forwards defense].flat_map { |group| Array(team_stats&.dig(group)) }.map { |player| player["playerId"] }
      player_ids.to_h do |player_id|
        [player_id, optional(game_id, "skater #{player_id} distance") {
          Nhl::EdgeClient.fetch_skater_skating_distance_detail(player_id, game_id: game_id, fresh: true)
        }]
      end
    end

    def optional(game_id, description)
      yield
    rescue Nhl::RequestError => e
      Rails.logger.warn "#{self.class.name}: game_id=#{game_id} skipping #{description}: #{e.message}"
      nil
    end

    def wait_for_data(game_id, attempt)
      if attempt < MAX_ATTEMPTS
        self.class.perform_in(RETRY_DELAY, attempt + 1)
      else
        Rails.logger.warn "#{self.class.name}: game_id=#{game_id} EDGE game data still unpublished after #{attempt} retries; giving up"
      end
    end

    def enqueue_once(game_id, posts)
      claim_key = "edge_recap:#{game_id}:claimed"
      return unless REDIS.set(claim_key, "1", nx: true, ex: CLAIM_TTL)

      begin
        PostThread.enqueue(posts, key: "edge_recap_#{game_id}")
      rescue
        REDIS.del(claim_key)
        raise
      end
    end
  end
end

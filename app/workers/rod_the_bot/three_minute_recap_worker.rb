module RodTheBot
  class ThreeMinuteRecapWorker
    include Sidekiq::Worker

    MAX_RETRIES = 6 # 1 hour max (6 retries * 10 minutes)

    def perform(game_id, retry_count = 0)
      boxscore = NhlApi.fetch_boxscore_feed(game_id)
      rr = NhlApi.fetch_right_rail_feed(game_id)
      gamedate = boxscore["gameDate"]
      game = get_game(gamedate, game_id)

      return if game.nil?
      return if game["gameScheduleState"] != "OK"

      if rr["gameVideo"].blank? || rr["gameVideo"]["threeMinRecap"].blank?
        if retry_count < MAX_RETRIES
          RodTheBot::ThreeMinuteRecapWorker.perform_in(600, game_id, retry_count + 1)
        else
          Rails.logger.warn "ThreeMinuteRecapWorker: Recap unavailable for game #{game_id} after #{retry_count} retries. Giving up."
        end
      else
        post = format_recap(game)
        recap_id = rr["gameVideo"]["threeMinRecap"]
        away_code = boxscore["awayTeam"]["abbrev"].downcase
        home_code = boxscore["homeTeam"]["abbrev"].downcase
        RodTheBot::Post.perform_async(post, nil, nil, "https://www.nhl.com/video/#{away_code}-at-#{home_code}-recap-#{recap_id}")
      end
    rescue NhlApi::APIError => e
      Rails.logger.error "ThreeMinuteRecapWorker: API error for game #{game_id}: #{e.message}"
    rescue => e
      Rails.logger.error "ThreeMinuteRecapWorker: Unexpected error for game #{game_id}: #{e.class} - #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
    end

    private

    def get_game(gamedate, game_id)
      schedule = NhlApi.fetch_league_schedule(date: gamedate)
      schedule["gameWeek"].each do |week|
        game = week["games"]&.find { |g| g["id"] == game_id }
        return game if game
      end
      nil
    end

    def format_recap(game)
      Time.zone = ENV["TIME_ZONE"]
      away_team = game["awayTeam"]["placeName"]["default"]
      home_team = game["homeTeam"]["placeName"]["default"]
      time = Time.zone.parse(game["startTimeUTC"])
      <<~POST
        The recap for #{away_team} at #{home_team} on #{time.strftime("%A, %B %d %Y")} is now available!
      POST
    end
  end
end

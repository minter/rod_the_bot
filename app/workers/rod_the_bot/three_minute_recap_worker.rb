module RodTheBot
  class ThreeMinuteRecapWorker
    include Sidekiq::Worker

    def perform(game_id)
      boxscore = NhlApi.fetch_boxscore_feed(game_id)
      gamedate = boxscore["gameDate"]
      game = get_game(gamedate, game_id)
      return if game.nil?
      return if game["gameScheduleState"] != "OK"
      if game["threeMinRecap"].blank?
        RodTheBot::ThreeMinuteRecapWorker.perform_in(600, game_id)
      else
        post = format_recap(game)
        RodTheBot::Post.perform_async(post, nil, nil, "https://nhl.com#{game["threeMinRecap"]}")
      end
    end

    private

    def get_game(gamedate, game_id)
      NhlApi.fetch_league_schedule(date: gamedate)["gameWeek"][0]["games"].find do |game|
        return game if game["id"] == game_id
      end
      nil
    end

    def format_recap(game)
      Time.zone = ENV["TIME_ZONE"]
      away_team = game["awayTeam"]["placeName"]["default"]
      home_team = game["homeTeam"]["placeName"]["default"]
      time = Time.zone.parse(game["startTimeUTC"])
      <<~POST
        The three-minute recap for #{away_team} at #{home_team} on #{time.strftime("%A, %B %d %Y")} is now available!
      POST
    end
  end
end

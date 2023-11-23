module RodTheBot
  require "sidekiq-scheduler"

  class Scheduler
    include Sidekiq::Worker
    include ActionView::Helpers::TextHelper
    include ActiveSupport::Inflector

    def perform
      @time_zone = TZInfo::Timezone.get(ENV["TIME_ZONE"])
      today = @time_zone.to_local(Time.now).strftime("%Y-%m-%d")
      @week = HTTParty.get("https://api-web.nhle.com/v1/club-schedule/#{ENV["NHL_TEAM_ABBREVIATION"]}/week/#{today}")

      RodTheBot::YesterdaysScoresWorker.perform_in(15.minutes)
      RodTheBot::DivisionStandingsWorker.perform_in(16.minutes)

      @game = @week["games"].find { |game| game["gameDate"] == today }

      return if @game.nil?

      time = @time_zone.to_local(Time.parse(@game["startTimeUTC"]))
      time_string = time.strftime("%l:%M %p").strip + " " + @time_zone.abbreviation
      home = @game["homeTeam"]
      away = @game["awayTeam"]
      venue = @game["venue"]

      game_id = @game["id"]

      away_standings = fetch_standings_info(away["abbrev"])
      home_standings = fetch_standings_info(home["abbrev"])

      your_team = if home["id"].to_i == ENV["NHL_TEAM_ID"].to_i
        home
      else
        away
      end

      your_standings = if home["id"].to_i == ENV["NHL_TEAM_ID"].to_i
        home_standings
      else
        away_standings
      end

      if away["id"].to_i == ENV["NHL_TEAM_ID"].to_i || home["id"].to_i == ENV["NHL_TEAM_ID"].to_i
        gameday_post = <<~POST
          🗣️ It's a #{your_standings[:team_name]} Gameday! 🗣️

          #{away_standings[:team_name]}
          #{record(away_standings)}

          at 

          #{home_standings[:team_name]}
          #{record(home_standings)}
          
          ⏰ #{time_string}
          📍 #{venue["default"]}
        POST

        RodTheBot::GameStream.perform_at(time - 15.minutes, game_id)
        RodTheBot::Post.perform_async(gameday_post)
        RodTheBot::SeasonStatsWorker.perform_async(your_standings[:team_name])
      end
    end

    def record(team)
      record = "(#{team[:wins]}-#{team[:losses]}-#{team[:ot]}, #{team[:points]} #{"point".pluralize(team[:points])})\n"
      record += "#{ordinalize team[:division_rank]} in the #{team[:division_name]}" unless team[:division_name] == "Unknown"
      record
    end

    def fetch_standings_info(team_abbreviation)
      response = HTTParty.get("https://api-web.nhle.com/v1/standings/now")
      team = response["standings"].find { |team| team["teamAbbrev"]["default"] == team_abbreviation }

      {
        division_name: team["divisionName"],
        division_rank: team["divisionSequence"],
        points: team["points"],
        wins: team["wins"],
        losses: team["losses"],
        ot: team["otLosses"],
        team_name: team["teamName"]["default"]
      }
    end
  end
end

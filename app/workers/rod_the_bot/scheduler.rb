module RodTheBot
  require "sidekiq-scheduler"

  class Scheduler
    include Sidekiq::Worker
    include ActionView::Helpers::TextHelper
    include ActiveSupport::Inflector

    def perform
      RodTheBot::YesterdaysScoresWorker.perform_in(5.minutes)
      if NhlApi.postseason?
        # Postseason
        RodTheBot::PostseasonSeriesWorker.perform_in(16.minutes)
      else
        RodTheBot::DivisionStandingsWorker.perform_in(16.minutes)
      end
      @game = NhlApi.todays_game

      return if @game.nil?

      time = Time.zone.parse(@game["startTimeUTC"])
      time_string = time.strftime("%l:%M %p").strip + " " + Time.zone.tzinfo.abbreviation
      home = @game["homeTeam"]
      away = @game["awayTeam"]
      your_team = (home["id"].to_i == ENV["NHL_TEAM_ID"].to_i) ? home : away
      @your_team_is = (home["id"].to_i == ENV["NHL_TEAM_ID"].to_i) ? "homeTeam" : "awayTeam"
      venue = @game["venue"]

      game_id = @game["id"]

      away_standings = NhlApi.team_standings(away["abbrev"])
      home_standings = NhlApi.team_standings(home["abbrev"])
      media = media(your_team)
      tv = media[:broadcast].empty? ? "None" : media[:broadcast].join(", ")

      your_standings = if home["id"].to_i == ENV["NHL_TEAM_ID"].to_i
        home_standings
      else
        away_standings
      end

      if away["id"].to_i == ENV["NHL_TEAM_ID"].to_i || home["id"].to_i == ENV["NHL_TEAM_ID"].to_i
        gameday_post = if NhlApi.preseason?(your_standings[:season_id])
          <<~POST
            🗣️ It's a #{your_standings[:team_name]} Preseason Gameday!

            #{away_standings[:team_name]}

            at 

            #{home_standings[:team_name]}
            
            ⏰ #{time_string}
            📍 #{venue["default"]}
            📺 #{tv}
          POST
        else
          <<~POST
            🗣️ It's a #{your_standings[:team_name]} Gameday!

            #{away_standings[:team_name]}
            #{record(away_standings)}

            at 

            #{home_standings[:team_name]}
            #{record(home_standings)}
            
            ⏰ #{time_string}
            📍 #{venue["default"]}
            📺 #{tv}
          POST
        end

        RodTheBot::GameStream.perform_at(time - 15.minutes, game_id)
        RodTheBot::Post.perform_async(gameday_post)
        RodTheBot::SeasonStatsWorker.perform_async(your_standings[:team_name])
      end
    end

    def media(team)
      media = {broadcast: []}
      @game["tvBroadcasts"].each do |broadcast|
        media[:broadcast] << broadcast["network"] if broadcast["countryCode"] == "US" && [@your_team_is[0].upcase, "N"].include?(broadcast["market"])
      end
      media[:radio] = @game[@your_team_is]["radioLink"]
      media[:tickets] = @game["ticketsLink"]
      media
    end

    def record(team)
      record = "(#{team[:wins]}-#{team[:losses]}-#{team[:ot]}, #{team[:points]} #{"point".pluralize(team[:points])})\n"
      record += "#{ordinalize team[:division_rank]} in the #{team[:division_name]}" unless team[:division_name] == "Unknown"
      record
    end
  end
end

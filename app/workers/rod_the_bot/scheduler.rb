module RodTheBot
  require "sidekiq-scheduler"

  class Scheduler
    include Sidekiq::Worker
    include ActionView::Helpers::TextHelper
    include ActiveSupport::Inflector

    def perform
      return if NhlApi.offseason?

      # if NhlApi.offseason?
      #   RodTheBot::DraftPickWorker.perform_async
      #   return
      # end
      RodTheBot::YesterdaysScoresWorker.perform_in(5.minutes)
      RodTheBot::TodaysScheduleWorker.perform_in(10.minutes)

      if NhlApi.postseason?
        # Postseason
        RodTheBot::PostseasonSeriesWorker.perform_in(16.minutes)
      else
        RodTheBot::DivisionStandingsWorker.perform_in(16.minutes)
      end
      @game = NhlApi.todays_game

      return if @game.nil? || @game["gameScheduleState"] != "OK"

      Time.zone = TZInfo::Timezone.get(ENV["TIME_ZONE"])
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
      away_logo_url = @game["awayTeam"]["logo"]
      home_logo_url = @game["homeTeam"]["logo"]
      media = media(your_team)
      tv = media[:broadcast].empty? ? "None" : media[:broadcast].join(", ")

      your_standings = if home["id"].to_i == ENV["NHL_TEAM_ID"].to_i
        home_standings
      else
        away_standings
      end

      if away["id"].to_i == ENV["NHL_TEAM_ID"].to_i || home["id"].to_i == ENV["NHL_TEAM_ID"].to_i
        gameday_post = if NhlApi.preseason?
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
        RodTheBot::Post.perform_async(gameday_post, nil, nil, nil, [away_logo_url, home_logo_url])
        RodTheBot::PlayerStreaksWorker.perform_in(3.minutes)
        RodTheBot::SeasonStatsWorker.perform_in(5.minutes, your_standings[:team_name])
        RodTheBot::UpcomingMilestonesWorker.perform_in(10.minutes)
        # EDGE stats posts
        RodTheBot::EdgeTeamPreviewWorker.perform_in(15.minutes, game_id)
        RodTheBot::EdgeTeamSpeedWorker.perform_in(17.minutes, game_id)
        RodTheBot::EdgeTeamShotSpeedWorker.perform_in(19.minutes, game_id)
        RodTheBot::EdgeMatchupWorker.perform_in(20.minutes, game_id)
        RodTheBot::EdgeSpeedMatchupWorker.perform_in(22.minutes, game_id)
        RodTheBot::EdgeShotSpeedMatchupWorker.perform_in(24.minutes, game_id)
        RodTheBot::EdgeSpecialTeamsWorker.perform_in(26.minutes, game_id)
        RodTheBot::EdgeEvenStrengthWorker.perform_in(27.minutes, game_id)
        RodTheBot::EdgeEsMatchupWorker.perform_in(29.minutes, game_id)
        RodTheBot::EdgeSpeedDemonLeaderboardWorker.perform_in(30.minutes, game_id)
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

    # Helper method to check if GameStreamWorker will be scheduled today
    def self.game_stream_scheduled_today?
      return false if NhlApi.offseason?

      game = NhlApi.todays_game
      return false if game.nil? || game["gameScheduleState"] != "OK"

      your_team_id = ENV["NHL_TEAM_ID"].to_i
      home_team_id = game["homeTeam"]["id"].to_i
      away_team_id = game["awayTeam"]["id"].to_i

      your_team_id == home_team_id || your_team_id == away_team_id
    end
  end
end

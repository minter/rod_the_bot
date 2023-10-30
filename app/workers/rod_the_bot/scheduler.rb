module RodTheBot
  require "sidekiq-scheduler"

  class Scheduler
    include Sidekiq::Worker
    include ActionView::Helpers::TextHelper
    include ActiveSupport::Inflector

    def perform
      @time_zone = TZInfo::Timezone.get(ENV["TIME_ZONE"])
      today = @time_zone.to_local(Time.now).strftime("%Y-%m-%d")
      @game = HTTParty.get("https://statsapi.web.nhl.com/api/v1/schedule?teamId=#{ENV["NHL_TEAM_ID"]}&date=#{today}")["dates"].first

      RodTheBot::YesterdaysScoresWorker.perform_in(15.minutes)
      RodTheBot::DivisionStandingsWorker.perform_in(16.minutes, ENV["NHL_TEAM_ID"])

      return if @game.nil?

      time = @time_zone.to_local(Time.parse(@game["games"].first["gameDate"]))
      time_string = time.strftime("%l:%M %p") + " " + @time_zone.abbreviation
      home = @game["games"].first["teams"]["home"]
      away = @game["games"].first["teams"]["away"]
      venue = @game["games"].first["venue"]

      game_id = @game["games"].first["gamePk"]

      your_team = if home["team"]["id"].to_i == ENV["NHL_TEAM_ID"].to_i
        home
      else
        away
      end

      if away["team"]["id"].to_i == ENV["NHL_TEAM_ID"].to_i || home["team"]["id"].to_i == ENV["NHL_TEAM_ID"].to_i
        gameday_post = <<~POST
          🗣️ It's a #{your_team["team"]["name"]} Gameday! 🗣️

          #{away["team"]["name"]}
          #{record(away)}

          at 

          #{home["team"]["name"]}
          #{record(home)}
          
          ⏰ #{time_string}
          📍 #{venue["name"]}
        POST

        RodTheBot::GameStream.perform_at(time - 15.minutes, game_id)
        RodTheBot::Post.perform_async(gameday_post)
        RodTheBot::SeasonStatsWorker.perform_async(your_team)
      end
    end

    def record(team)
      points = team["leagueRecord"]["wins"] * 2 + team["leagueRecord"]["ot"]
      rank = fetch_division_info(team["team"]["id"])
      record = "(#{team["leagueRecord"]["wins"]}-#{team["leagueRecord"]["losses"]}-#{team["leagueRecord"]["ot"]}, #{points} #{"point".pluralize(points)})\n"
      record += "#{ordinalize rank[:division_rank]} in the #{rank[:division_name]}" unless rank[:division_name] == "Unknown"
      record
    end

    def fetch_division_info(team_id)
      response = HTTParty.get("https://statsapi.web.nhl.com/api/v1/standings")
      standings = response["records"]

      standings.each do |division|
        division["teamRecords"].each do |team|
          if team["team"]["id"].to_i == team_id.to_i
            return {
              division_name: division["division"]["name"],
              division_rank: team["divisionRank"]
            }
          end
        end
      end

      {
        division_name: "Unknown",
        division_rank: "Unknown"
      }
    end
  end
end

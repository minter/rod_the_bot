module RodTheBot
  class TodaysScheduleWorker
    include Sidekiq::Worker

    def perform
      date = Date.today.strftime("%Y-%m-%d")
      schedule = NhlApi.fetch_league_schedule(date: date)
      formatted_schedule = format_schedule(schedule, date)
      time_zone_abbr = Time.zone.tzinfo.abbreviation
      playoffs = NhlApi.postseason? ? "playoff " : ""
      post_text = "🗓️  Today's NHL #{playoffs}schedule (times #{time_zone_abbr})\n\n#{formatted_schedule}\n"
      RodTheBot::Post.perform_async(post_text)
    end

    private

    def format_schedule(schedule, date)
      Time.zone = TZInfo::Timezone.get(ENV["TIME_ZONE"])
      today_games = schedule["gameWeek"].find { |day| day["date"] == date }&.dig("games")

      return "No games scheduled." if today_games.nil? || today_games.empty?

      today_games.map do |game|
        visitor = game["awayTeam"]["abbrev"]
        home = game["homeTeam"]["abbrev"]
        game_time = format_game_time(game)
        output = "#{visitor} @ #{home} - #{game_time}"
        output += series_status(game) if game["seriesStatus"]
        output
      end.join("\n")
    end

    def series_status(game)
      status = game["seriesStatus"]
      top_seed_abbrev = status["topSeedTeamAbbrev"]
      top_seed_wins = status["topSeedWins"]
      bottom_seed_abbrev = status["bottomSeedTeamAbbrev"]
      bottom_seed_wins = status["bottomSeedWins"]

      if top_seed_wins == bottom_seed_wins
        " (Series tied at #{top_seed_wins})"
      elsif top_seed_wins > bottom_seed_wins
        " (#{top_seed_abbrev} leads #{top_seed_wins}-#{bottom_seed_wins})"
      else
        " (#{bottom_seed_abbrev} leads #{bottom_seed_wins}-#{top_seed_wins})"
      end
    end

    def format_game_time(game)
      if game["gameScheduleState"] == "OK"
        local_time = Time.zone.parse(game["startTimeUTC"])
        if local_time.min.zero?
          local_time.strftime("%-I %p").sub(/^0/, "")
        else
          local_time.strftime("%-I:%M %p")
        end
      else
        game["gameScheduleState"]
      end
    end
  end
end

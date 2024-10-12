module RodTheBot
  class TodaysScheduleWorker
    include Sidekiq::Worker

    def perform
      date = Date.today.strftime("%Y-%m-%d")
      schedule = NhlApi.fetch_league_schedule(date: date)
      formatted_schedule = format_schedule(schedule, date)
      time_zone_abbr = Time.zone.tzinfo.abbreviation
      post_text = "🗓️  Today's NHL schedule (times #{time_zone_abbr})\n\n#{formatted_schedule}\n"
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
        "#{visitor} @ #{home} - #{game_time}"
      end.join("\n")
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

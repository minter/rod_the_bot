module RodTheBot
  class TodaysScheduleWorker
    include Sidekiq::Worker

    def perform
      date = Date.today.strftime("%Y-%m-%d")
      schedule = Nhl::ScheduleClient.league_schedule(date: date)
      games = format_schedule(schedule, date)
      time_zone_abbr = Time.zone.tzinfo.abbreviation
      playoffs = Nhl::SeasonCalendar.postseason? ? "playoff " : ""

      # Handle no games case
      if games.empty?
        post_text = "🗓️  Today's NHL #{playoffs}schedule (times #{time_zone_abbr})\n\nNo games scheduled.\n"
        RodTheBot::Post.perform_async(post_text)
        return
      end

      # Check if we need to split into multiple posts
      base_text = "🗓️  Today's NHL #{playoffs}schedule (times #{time_zone_abbr})\n\n"
      formatted_schedule = games.join("\n")
      full_text = "#{base_text}#{formatted_schedule}\n"

      # Account for hashtags that will be added by Post worker
      hashtags = ENV["TEAM_HASHTAGS"] || ""
      hashtag_length = hashtags.empty? ? 0 : hashtags.length + 1 # +1 for newline
      max_content_length = 300 - hashtag_length

      if full_text.length <= max_content_length
        # Single post if it fits
        RodTheBot::Post.perform_async(full_text)
      else
        # Split into multiple posts
        post_schedule_in_thread(games, base_text, max_content_length)
      end
    end

    private

    def format_schedule(schedule, date)
      Time.zone = TZInfo::Timezone.get(ENV["TIME_ZONE"])
      today_games = schedule["gameWeek"].find { |day| day["date"] == date }&.dig("games")

      return [] if today_games.nil? || today_games.empty?

      today_games.map do |game|
        visitor = game["awayTeam"]["abbrev"]
        home = game["homeTeam"]["abbrev"]
        game_time = format_game_time(game)
        output = "#{visitor} @ #{home} - #{game_time}"
        output += series_status(game) if game["seriesStatus"]
        output
      end
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

    def post_schedule_in_thread(games, base_text, max_content_length)
      # Generate unique keys for threading
      current_date = Time.now.strftime("%Y%m%d")
      base_key = "todays_schedule:#{current_date}"

      # Split games into chunks that fit within character limit
      game_chunks = split_games_into_chunks(games, base_text, max_content_length)

      return if game_chunks.empty?

      PostThread.enqueue(game_chunks, key: base_key)
    end

    def split_games_into_chunks(games, base_text, max_content_length)
      PostThread.split_lines(games.map { |game| "#{game}\n" }, header: base_text, limit: max_content_length)
    end
  end
end

module RodTheBot
  require "sidekiq-scheduler"

  class Scheduler
    include Sidekiq::Worker

    def perform
      if Nhl::SeasonCalendar.offseason?
        RodTheBot::DraftPickWorker.perform_async
        return
      end

      RodTheBot::YesterdaysScoresWorker.perform_in(5.minutes)
      RodTheBot::TodaysScheduleWorker.perform_in(10.minutes)

      if Nhl::SeasonCalendar.postseason?
        # Postseason
        RodTheBot::PostseasonSeriesWorker.perform_in(16.minutes)
      else
        RodTheBot::DivisionStandingsWorker.perform_in(16.minutes)
      end
      @game = Nhl::ScheduleClient.todays_game

      return if @game.nil? || @game["gameScheduleState"] != "OK"

      Time.zone = TZInfo::Timezone.get(ENV["TIME_ZONE"])
      time = Time.zone.parse(@game["startTimeUTC"])
      home = @game["homeTeam"]
      away = @game["awayTeam"]
      your_team = (home["id"].to_i == ENV["NHL_TEAM_ID"].to_i) ? home : away
      @your_team_is = (home["id"].to_i == ENV["NHL_TEAM_ID"].to_i) ? "homeTeam" : "awayTeam"
      @game["venue"]

      game_id = @game["id"]

      away_standings = standings_for(away)
      home_standings = standings_for(home)
      media = media(your_team)
      tv = media[:broadcast].empty? ? "None" : media[:broadcast].join(", ")

      your_standings = if home["id"].to_i == ENV["NHL_TEAM_ID"].to_i
        home_standings
      else
        away_standings
      end

      if away["id"].to_i == ENV["NHL_TEAM_ID"].to_i || home["id"].to_i == ENV["NHL_TEAM_ID"].to_i
        preseason = Nhl::SeasonCalendar.preseason?
        postseason = Nhl::SeasonCalendar.postseason? && @game["seriesStatus"].present?
        seeds = postseason ? Nhl::StandingsClient.playoff_seed_labels : {}
        series = postseason ? @game["seriesStatus"].merge(series_seed_abbrevs(@game["seriesStatus"]["seriesLetter"])) : nil
        gameday_post = Scheduling::GamedayPost.new.build(
          game: @game,
          away: away_standings.merge(abbrev: away["abbrev"]),
          home: home_standings.merge(abbrev: home["abbrev"]),
          tracked: your_standings,
          starts_at: time,
          time_zone: ENV.fetch("TIME_ZONE"),
          television: tv,
          preseason: preseason,
          postseason: postseason,
          seed_labels: seeds,
          series_status: series
        )

        gameday_key = "gameday_#{game_id}"
        RodTheBot::GameStream.perform_at(time - 15.minutes, game_id)
        RodTheBot::Post.perform_async(
          gameday_post,
          {"key" => gameday_key, "embed_images" => gameday_images}
        )
        schedule_gameday_details(game_id, gameday_key, media, preseason: preseason, game_type: @game["gameType"])
        RodTheBot::PlayerStreaksWorker.perform_in(3.minutes)
        RodTheBot::SeasonStatsWorker.perform_in(5.minutes, your_standings[:team_name])
        RodTheBot::UpcomingMilestonesWorker.perform_in(10.minutes)

        # Schedule EDGE stats posts dynamically based on time until game
        schedule_edge_posts(game_id, time)
      end
    end

    def schedule_edge_posts(game_id, game_time)
      Scheduling::EdgePosts.new.schedule(game_id: game_id, game_time: game_time)
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

    # Helper method to check if GameStreamWorker will be scheduled today
    def self.game_stream_scheduled_today?
      return false if Nhl::SeasonCalendar.offseason?

      game = Nhl::ScheduleClient.todays_game
      return false if game.nil? || game["gameScheduleState"] != "OK"

      your_team_id = ENV["NHL_TEAM_ID"].to_i
      home_team_id = game["homeTeam"]["id"].to_i
      away_team_id = game["awayTeam"]["id"].to_i

      your_team_id == home_team_id || your_team_id == away_team_id
    end

    private

    def schedule_gameday_details(game_id, gameday_key, media, preseason:, game_type:)
      series = season_series(game_id, preseason: preseason, game_type: game_type)
      details = Scheduling::GamedayDetailsPost.new.build(
        series: series,
        radio_url: media[:radio],
        tickets_url: media[:tickets]
      )
      return unless details

      RodTheBot::Post.perform_in(
        1.minute,
        details[:text],
        {
          "key" => "gameday_details_#{game_id}",
          "parent_key" => gameday_key,
          "links" => details[:links]
        }
      )
    end

    def season_series(game_id, preseason:, game_type:)
      return if preseason || game_type.to_i != 2

      Nhl::GameInfo.season_series(game_id)
    rescue Nhl::RequestError => e
      Rails.logger.warn "Scheduler: Season-series data unavailable for game #{game_id}: #{e.message}"
      nil
    end

    def gameday_images
      special_event_logo = @game.dig("specialEvent", "lightLogoUrl", "default")
      return [special_event_logo] if special_event_logo.present?

      [@game.dig("awayTeam", "logo"), @game.dig("homeTeam", "logo")].compact
    end

    def standings_for(team)
      standings = if @game["season"]
        Nhl::StandingsClient.team(team["abbrev"], season: @game["season"])
      else
        Nhl::StandingsClient.team(team["abbrev"])
      end
      return standings if standings

      {
        team_name: [team.dig("placeName", "default"), team.dig("commonName", "default")].compact.join(" ").presence || team["abbrev"]
      }
    end

    def series_seed_abbrevs(series_letter)
      return {} unless series_letter

      carousel = Nhl::ScheduleClient.postseason_carousel
      return {} unless carousel

      series = (carousel["rounds"] || []).flat_map { |round| round["series"] || [] }
        .find { |s| s["seriesLetter"] == series_letter }
      return {} unless series

      {
        "topSeedTeamAbbrev" => series.dig("topSeed", "abbrev"),
        "bottomSeedTeamAbbrev" => series.dig("bottomSeed", "abbrev")
      }.compact
    end
  end
end

module RodTheBot
  class GoalWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector
    include RodTheBot::PeriodFormatter

    def perform(game_id, play)
      @feed = NhlApi.fetch_pbp_feed(game_id)
      @play_id = play["eventId"]
      @play = NhlApi.fetch_play(game_id, @play_id)

      return if @play.blank?

      # Skip goals in the shootout
      return if @play["periodDescriptor"]["periodType"] == "SO"

      home = @feed["homeTeam"]
      away = @feed["awayTeam"]
      if home["id"].to_i == ENV["NHL_TEAM_ID"].to_i
        @your_team = home
        @their_team = away
      else
        @your_team = away
        @their_team = home
      end

      players = NhlApi.game_rosters(game_id)

      original_play = @play.deep_dup

      if @play["details"]["scoringPlayerId"].blank?
        RodTheBot::GoalWorker.perform_in(60, game_id, @play)
        return
      end

      period_name = format_period_name(@play["periodDescriptor"]["number"])
      modifiers = modifiers(@play["situationCode"].to_s, players[@play["details"]["scoringPlayerId"]][:team_id], home["id"], away["id"])

      scoring_team = (players[@play["details"]["scoringPlayerId"]][:team_id] == ENV["NHL_TEAM_ID"].to_i) ? @your_team : @their_team

      post = build_post(
        scoring_team: scoring_team,
        modifiers: modifiers,
        players: players,
        play: @play,
        period_name: period_name,
        away: away,
        home: home
      )

      redis_key = "game:#{game_id}:goal:#{@play_id}"
      RodTheBot::Post.perform_async(post, redis_key, nil, nil, goal_images(players, @play))
      RodTheBot::ScoringChangeWorker.perform_in(600, game_id, play["eventId"], original_play, redis_key)
      RodTheBot::GoalHighlightWorker.perform_in(10, game_id, play["eventId"], redis_key) if scoring_team == @your_team
    end

    def build_post(scoring_team:, modifiers:, players:, play:, period_name:, away:, home:)
      [
        goal_header(scoring_team, modifiers),
        "",
        goal_details(players, play),
        time_and_score(play, period_name, away, home),
        ""  # Add an extra empty line at the end
      ].join("\n")
    end

    def goal_header(scoring_team, modifiers)
      if scoring_team == @your_team
        "🎉 #{scoring_team["name"]["default"]}#{modifiers} GOOOOOOOAL!"
      else
        "👎 #{scoring_team["name"]["default"]}#{modifiers} Goal"
      end
    end

    def goal_details(players, play)
      details = []
      details << "🚨 #{players[play["details"]["scoringPlayerId"]][:name]} (#{play["details"]["scoringPlayerTotal"]})"

      details << if play["details"]["assist1PlayerId"].present?
        "🍎 #{players[play["details"]["assist1PlayerId"]][:name]} (#{play["details"]["assist1PlayerTotal"]})"
      else
        "🍎 Unassisted"
      end

      if play["details"]["assist2PlayerId"].present?
        details << "🍎🍎 #{players[play["details"]["assist2PlayerId"]][:name]} (#{play["details"]["assist2PlayerTotal"]})"
      end

      details.join("\n")
    end

    def goal_images(players, play)
      images = []
      images << NhlApi.fetch_player_landing_feed(play["details"]["scoringPlayerId"])["headshot"]
      images << NhlApi.fetch_player_landing_feed(play["details"]["assist1PlayerId"])["headshot"] if play["details"]["assist1PlayerId"].present?
      images << NhlApi.fetch_player_landing_feed(play["details"]["assist2PlayerId"])["headshot"] if play["details"]["assist2PlayerId"].present?
      images
    end

    def time_and_score(play, period_name, away, home)
      [
        "⏱️  #{play["timeInPeriod"]} #{period_name}",
        "",
        "#{away["abbrev"]} #{play["details"]["awayScore"]} - #{home["abbrev"]} #{play["details"]["homeScore"]}"
      ].join("\n")
    end

    def modifiers(situation_code, scoring_team_id, home_id, away_id)
      away_goalies, away_skaters, home_skaters, home_goalies = situation_code.chars.map(&:to_i)
      away_players = away_goalies + away_skaters
      home_players = home_goalies + home_skaters

      scoring_team_players, opposing_team_players, opposing_team_goalies =
        if scoring_team_id == home_id
          [home_players, away_players, away_goalies]
        else
          [away_players, home_players, home_goalies]
        end

      modifiers = []
      modifiers << "Shorthanded" if scoring_team_players < opposing_team_players
      modifiers << "Power Play" if scoring_team_players > opposing_team_players
      modifiers << "Empty Net" if opposing_team_goalies == 0

      modifiers.empty? ? "" : " " + modifiers.join(", ")
    end
  end
end

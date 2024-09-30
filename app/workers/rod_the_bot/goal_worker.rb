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

      post = if players[@play["details"]["scoringPlayerId"]][:team_id] == ENV["NHL_TEAM_ID"].to_i
        "🎉 #{@your_team["name"]["default"]}#{modifiers} GOOOOOOOAL!\n\n"
      else
        "👎 #{@their_team["name"]["default"]}#{modifiers} Goal\n\n"
      end

      post += "🚨 #{players[@play["details"]["scoringPlayerId"]][:name]} (#{@play["details"]["scoringPlayerTotal"]})\n"

      post += if @play["details"]["assist1PlayerId"].present?
        "🍎 #{players[@play["details"]["assist1PlayerId"]][:name]} (#{@play["details"]["assist1PlayerTotal"]})\n"
      else
        "🍎 Unassisted\n"
      end
      post += "🍎🍎 #{players[@play["details"]["assist2PlayerId"]][:name]} (#{@play["details"]["assist2PlayerTotal"]})\n" if @play["details"]["assist2PlayerId"].present?

      post += "⏱️  #{@play["timeInPeriod"]} #{period_name}\n\n"
      post += "#{away["abbrev"]} #{@play["details"]["awayScore"]} - #{home["abbrev"]} #{@play["details"]["homeScore"]}\n"
      RodTheBot::Post.perform_async(post, "#{game_id}:#{@play_id}")
      RodTheBot::ScoringChangeWorker.perform_in(600, game_id, play["eventId"], original_play)
      RodTheBot::GoalHighlightWorker.perform_in(300, game_id, play["eventId"]) if players[@play["details"]["scoringPlayerId"]][:team_id] == ENV["NHL_TEAM_ID"].to_i
    end

    def modifiers(situation_code, scoring_team_id, home_id, away_id)
      away_goalies = situation_code[0].to_i
      away_skaters = situation_code[1].to_i
      home_skaters = situation_code[2].to_i
      home_goalies = situation_code[3].to_i
      away_players = away_goalies + away_skaters
      home_players = home_goalies + home_skaters
      modifiers = []

      if scoring_team_id == home_id
        modifiers << "Shorthanded" if away_players > home_players
        modifiers << "Power Play" if away_players < home_players
        modifiers << "Empty Net" if away_goalies == 0
      else
        modifiers << "Shorthanded" if home_players > away_players
        modifiers << "Power Play" if home_players < away_players
        modifiers << "Empty Net" if home_goalies == 0
      end
      modifiers.empty? ? "" : " " + modifiers.join(", ")
    end
  end
end

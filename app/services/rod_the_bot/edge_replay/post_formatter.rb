module RodTheBot
  module EdgeReplay
    class PostFormatter
      include RodTheBot::PeriodFormatter
      include RodTheBot::PlayerFormatter

      def format(play, players, feed)
        scorer_id = play.dig("details", "scoringPlayerId")
        scorer = scorer_id ? format_player_from_roster(players, scorer_id) : "Unknown Player"
        scoring_team = feed[feed.dig("homeTeam", "id") == play.dig("details", "eventOwnerTeamId") ? "homeTeam" : "awayTeam"]["abbrev"]
        period = format_period_name(play.dig("periodDescriptor", "number"))

        assists = %w[assist1PlayerId assist2PlayerId].filter_map do |key|
          player_id = play.dig("details", key)
          format_player_from_roster(players, player_id) if player_id.present?
        end
        assist_text = assists.empty? ? "" : " Assisted by #{assists.join(", ")}."

        away = feed.dig("awayTeam", "abbrev")
        home = feed.dig("homeTeam", "abbrev")
        score = format("%s %d - %s %d", away, play.dig("details", "awayScore") || 0, home, play.dig("details", "homeScore") || 0)

        "📊 EDGE replay: #{scorer} (#{scoring_team}) scores at #{play["timeInPeriod"]} of the #{period}." \
          "#{assist_text} Score: #{score}"
      end
    end
  end
end

module RodTheBot
  module ScoringChange
    class Formatter
      include RodTheBot::PeriodFormatter

      CHALLENGES = {
        "chlg-hm-goal-interference" => "goaltender interference challenge",
        "chlg-hm-missed-stoppage" => "missed stoppage challenge",
        "chlg-hm-off-side" => "offside challenge",
        "chlg-vis-goal-interference" => "goaltender interference challenge",
        "chlg-vis-missed-stoppage" => "missed stoppage challenge",
        "chlg-vis-off-side" => "offside challenge",
        "chlg-league-goal-interference" => "league review for goaltender interference",
        "chlg-league-missed-stoppage" => "league review for missed stoppage",
        "chlg-league-off-side" => "league review for offside"
      }.freeze

      def correction(play:, scoring_team:, players:)
        period = format_period_name(play.dig("periodDescriptor", "number"))
        details = play.fetch("details")
        post = <<~POST
          🔔 Scoring Change

          The #{scoring_team.dig("commonName", "default")} goal at #{play["timeInPeriod"]} of the #{period} now reads:

        POST
        post << "🚨 #{players.name_with_number(details["scoringPlayerId"])} (#{details["scoringPlayerTotal"]})\n"
        post << if details["assist1PlayerId"].present?
          "🍎 #{players.name_with_number(details["assist1PlayerId"])} (#{details["assist1PlayerTotal"]})\n"
        else
          "🍎 Unassisted\n"
        end
        post << "🍎🍎 #{players.name_with_number(details["assist2PlayerId"])} (#{details["assist2PlayerTotal"]})\n" if details["assist2PlayerId"].present?
        post
      end

      def overturn(original_play:, scoring_team:, challenge:, home:, away:, players:)
        reason_code = challenge.dig("details", "reason")
        reason = CHALLENGES.fetch(reason_code, "video review")
        challenger = reason_code.include?("chlg-hm") ? home : (away if reason_code.include?("chlg-vis"))
        scorer = players.full_name(original_play.dig("details", "scoringPlayerId"))
        period = format_period_name(original_play.dig("periodDescriptor", "number"))
        team_name = scoring_team.dig("placeName", "default")
        review = challenger ? "successful #{reason} by #{challenger.dig("placeName", "default")}" : reason

        <<~POST
          ❌ Goal Overturned

          The #{team_name} goal by #{scorer} at #{original_play["timeInPeriod"]} of the #{period} has been disallowed following a #{review}.
        POST
      end
    end
  end
end

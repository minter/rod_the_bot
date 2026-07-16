module RodTheBot
  module Goal
    class PostBuilder
      include RodTheBot::PeriodFormatter

      Result = Data.define(:post, :scoring_team, :your_team, :penalty_shot)

      def initialize(team_id: ENV.fetch("NHL_TEAM_ID").to_i)
        @team_id = team_id
      end

      def build(play:, feed:, players:)
        home = feed.fetch("homeTeam")
        away = feed.fetch("awayTeam")
        your_team, their_team = (home["id"].to_i == team_id) ? [home, away] : [away, home]
        scorer = players.fetch(play.dig("details", "scoringPlayerId"))
        return unless scorer

        scoring_team = (scorer.team_id == team_id) ? your_team : their_team
        situation = Situation.new(play["situationCode"].to_s, scoring_team_id: scorer.team_id, home_id: home["id"], away_id: away["id"])
        period = format_period_name(play.dig("periodDescriptor", "number"))
        post = [header(scoring_team, your_team, situation.modifiers), "", details(players, play), score(play, period, away, home), ""].join("\n")

        Result.new(post: post, scoring_team: scoring_team, your_team: your_team, penalty_shot: situation.penalty_shot?)
      end

      private

      attr_reader :team_id

      def header(scoring_team, your_team, modifiers)
        (scoring_team == your_team) ? "🎉 #{scoring_team.dig("commonName", "default")}#{modifiers} GOOOOOOOAL!" : "👎 #{scoring_team.dig("commonName", "default")}#{modifiers} Goal"
      end

      def details(players, play)
        data = play.fetch("details")
        lines = ["🚨 #{players.name_with_number(data["scoringPlayerId"])} (#{data["scoringPlayerTotal"]})"]
        lines << if data["assist1PlayerId"].present?
          "🍎 #{players.name_with_number(data["assist1PlayerId"])} (#{data["assist1PlayerTotal"]})"
        else
          "🍎 Unassisted"
        end
        lines << "🍎🍎 #{players.name_with_number(data["assist2PlayerId"])} (#{data["assist2PlayerTotal"]})" if data["assist2PlayerId"].present?
        lines.join("\n")
      end

      def score(play, period, away, home)
        "⏱️  #{play["timeInPeriod"]} #{period}\n\n#{away["abbrev"]} #{play.dig("details", "awayScore")} - #{home["abbrev"]} #{play.dig("details", "homeScore")}"
      end
    end
  end
end

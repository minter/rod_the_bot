module RodTheBot
  class ShotChartAnimator
    module ShotExtractor
      extend self

      PLOTTABLE_TYPES = %w[shot-on-goal goal].freeze

      def call(feed:, through_period:)
        plays = Array(feed["plays"])
        home_id = feed.dig("homeTeam", "id")
        away_id = feed.dig("awayTeam", "id")

        shots = plays.filter_map do |play|
          next unless PLOTTABLE_TYPES.include?(play["typeDescKey"])

          period = play.dig("periodDescriptor", "number").to_i
          next if period <= 0 || period > through_period

          details = play["details"] || {}
          x = details["xCoord"]
          y = details["yCoord"]
          next if x.nil? || y.nil?

          nx, ny = CoordNormalizer.normalize(
            x: x, y: y,
            home_defending_side: play["homeTeamDefendingSide"]
          )

          team_id = details["eventOwnerTeamId"]
          team_side = if team_id == home_id then :home
          elsif team_id == away_id then :away
          else :unknown
          end

          {
            event_id: play["eventId"],
            period: period,
            time_in_period: play["timeInPeriod"],
            type: play["typeDescKey"],
            x: nx,
            y: ny,
            team_id: team_id,
            team_side: team_side,
            away_score: details["awayScore"],
            home_score: details["homeScore"]
          }
        end

        shots.sort_by { |s| [s[:period], s[:time_in_period].to_s.split(":").map(&:to_i)] }
      end
    end
  end
end

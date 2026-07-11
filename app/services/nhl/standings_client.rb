module Nhl
  class StandingsClient < Client
    base_uri "https://api-web.nhle.com/v1"

    class << self
      def standings
        Rails.cache.fetch("standings", expires_in: 8.hours) { get_json("/standings/now") }
      end

      def playoff_seed_labels
        standings.fetch("standings", []).each_with_object({}) do |team, labels|
          abbrev = team.dig("teamAbbrev", "default")
          next unless abbrev

          wildcard = team["wildcardSequence"].to_i
          labels[abbrev] = wildcard.positive? ? "WC#{wildcard}" : division_seed(team)
        end.compact
      end

      def team(team_abbreviation)
        entry = standings.fetch("standings", []).find { |candidate| candidate.dig("teamAbbrev", "default") == team_abbreviation }
        return unless entry

        {
          division_name: entry["divisionName"], division_rank: entry["divisionSequence"],
          points: entry["points"], wins: entry["wins"], losses: entry["losses"],
          ot: entry["otLosses"], team_name: entry.dig("teamName", "default"), season_id: entry["seasonId"]
        }
      end

      private

      def division_seed(team)
        division = team["divisionAbbrev"]
        sequence = team["divisionSequence"]
        "#{division}#{sequence}" if division && sequence
      end
    end
  end
end

module Nhl
  class Roster < Client
    base_uri "https://api-web.nhle.com/v1"

    class << self
      def for(team_abbreviation)
        Rails.cache.fetch("team_roster_#{team_abbreviation}", expires_in: 5.hours) do
          groups = raw(team_abbreviation)
          %w[forwards defensemen goalies].flat_map { |group| groups.fetch(group, []) }.to_h do |player|
            normalized = normalize(player, team_abbreviation)
            [normalized[:id], normalized]
          end
        end
      end

      def raw(team_abbreviation)
        get_json("/roster/#{team_abbreviation}/current")
      end

      private

      def normalize(player, team_abbreviation)
        identity = PlayerIdentity.from_team_roster(player, team_abbreviation: team_abbreviation)
        normalized = player.deep_symbolize_keys
        normalized[:firstName] = identity.first_name
        normalized[:lastName] = identity.last_name
        normalized[:fullName] = identity.full_name
        normalized[:birthCity] = localized(normalized[:birthCity])
        normalized[:birthStateProvince] = localized(normalized[:birthStateProvince])
        normalized[:name_number] = identity.name_with_number
        normalized
      end

      def localized(value)
        value&.fetch(:default, nil) || value&.values&.first
      end
    end
  end
end

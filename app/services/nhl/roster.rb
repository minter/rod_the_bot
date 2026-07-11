module Nhl
  class Roster < Client
    base_uri "https://api-web.nhle.com/v1"

    class << self
      def for(team_abbreviation)
        Rails.cache.fetch("team_roster_#{team_abbreviation}", expires_in: 5.hours) do
          groups = get_json("/roster/#{team_abbreviation}/current")
          %w[forwards defensemen goalies].flat_map { |group| groups.fetch(group, []) }.to_h do |player|
            normalized = normalize(player)
            [normalized[:id], normalized]
          end
        end
      end

      private

      def normalize(player)
        player = player.deep_symbolize_keys
        player[:firstName] = player.dig(:firstName, :default)
        player[:lastName] = player.dig(:lastName, :default)
        player[:fullName] = "#{player[:firstName]} #{player[:lastName]}"
        player[:birthCity] = localized(player[:birthCity])
        player[:birthStateProvince] = localized(player[:birthStateProvince])
        player[:name_number] = "##{player[:sweaterNumber]} #{player[:fullName]}"
        player
      end

      def localized(value)
        value&.fetch(:default, nil) || value&.values&.first
      end
    end
  end
end

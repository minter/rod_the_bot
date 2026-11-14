module Nhl
  # The NHL records site, which holds all-time franchise totals that the game and stats
  # APIs do not.
  class RecordsClient < Client
    base_uri "https://records.nhl.com/site/api"

    class << self
      # Regular-season career totals for everyone who has played for the franchise,
      # including its earlier names and cities.
      def franchise_skater_totals(franchise_id)
        Rails.cache.fetch("franchise_skater_totals_#{franchise_id}", expires_in: 6.hours) do
          query = URI.encode_www_form(cayenneExp: "franchiseId=#{franchise_id}")
          get_json("/skater-career-scoring-regular-season?#{query}").fetch("data", []).map do |row|
            {
              player_id: row["playerId"].to_i,
              name: PlayerIdentity.new(id: row["playerId"], first_name: row["firstName"], last_name: row["lastName"]).full_name,
              goals: row["goals"].to_i,
              assists: row["assists"].to_i,
              points: row["points"].to_i
            }
          end
        end
      end
    end
  end
end

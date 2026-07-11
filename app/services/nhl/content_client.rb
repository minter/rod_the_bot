module Nhl
  class ContentClient < Client
    base_uri "https://forge-dapi.d3.nhle.com/v2/content/en-us"

    def self.player(player_id)
      Rails.cache.fetch("player_content_#{player_id}", expires_in: 8.hours) do
        get_json("/players?tags.slug=playerid-#{player_id}")
      end
    end
  end
end

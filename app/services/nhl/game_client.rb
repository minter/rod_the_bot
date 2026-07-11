module Nhl
  class GameClient < Client
    base_uri "https://api-web.nhle.com/v1"

    class << self
      def play_by_play(game_id)
        get_json("/gamecenter/#{game_id}/play-by-play")
      end

      def play(game_id, play_id)
        feed = play_by_play(game_id)
        feed["plays"]&.find { |candidate| candidate["eventId"].to_s == play_id.to_s }
      end

      def boxscore(game_id)
        get_json("/gamecenter/#{game_id}/boxscore")
      end

      def landing(game_id)
        get_json("/gamecenter/#{game_id}/landing")
      end

      def right_rail(game_id)
        get_json("/gamecenter/#{game_id}/right-rail")
      end

      def player_landing_feed(player_id)
        Rails.cache.fetch("player_landing_feed_#{player_id}", expires_in: 8.hours) do
          get_json("/player/#{player_id}/landing")
        end
      end
    end
  end
end

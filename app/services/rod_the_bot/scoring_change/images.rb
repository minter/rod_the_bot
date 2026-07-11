module RodTheBot
  module ScoringChange
    class Images
      def self.for(play)
        %w[scoringPlayerId assist1PlayerId assist2PlayerId].filter_map do |key|
          player_id = play.dig("details", key)
          Nhl::PlayerClient.landing(player_id).dig("headshot") if player_id.present?
        end
      end
    end
  end
end

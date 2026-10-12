module RodTheBot
  class EdgeHotZones
    ELITE_PERCENTILE = 0.80

    # A high percentile with zero goals is meaningless (everyone is tied at 0),
    # so a zone only counts when the player has actually scored there.
    def self.elite(shot_location_details)
      Array(shot_location_details)
        .select { |zone| zone["goals"].to_i.positive? && zone["goalsPercentile"].to_f >= ELITE_PERCENTILE }
        .sort_by { |zone| -zone["goalsPercentile"] }
    end
  end
end

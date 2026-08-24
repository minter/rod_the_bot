module Nhl
  class GameId
    attr_reader :value

    def initialize(value)
      @value = value.to_s.strip
      raise ArgumentError, "Invalid game_id" unless @value.match?(/\A\d{10}\z/)
    end

    def season
      start_year = value.first(4).to_i
      "#{start_year}#{start_year + 1}"
    end

    def game_type
      value[4, 2].to_i
    end
  end
end

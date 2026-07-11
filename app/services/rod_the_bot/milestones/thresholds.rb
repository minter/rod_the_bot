module RodTheBot
  module Milestones
    module Thresholds
      VALUES = {
        "goal" => [1, 50, 100, 200, 250, 300, 400, 500],
        "point" => [1, 50, 100, 200, 250, 300, 400, 500, 600, 700, 750, 800, 900, 1000],
        "assist" => [50, 100, 200, 250, 300, 400, 500, 600, 700, 750, 800, 900, 1000],
        "win" => [1, 50, 100, 200, 300, 400, 500],
        "shutout" => [1, 10, 20, 30, 40, 50, 100]
      }.freeze

      def self.include?(type, value)
        VALUES.fetch(type).include?(value)
      end
    end
  end
end

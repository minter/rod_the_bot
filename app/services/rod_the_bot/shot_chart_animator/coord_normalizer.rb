class RodTheBot::ShotChartAnimator
  module CoordNormalizer
    CANVAS_WIDTH  = 1200
    CANVAS_HEIGHT = 510
    NHL_X_RANGE   = 200.0
    NHL_Y_RANGE   = 85.0

    extend self

    # Canonical orientation: home team always attacks right.
    # Flip both coords for periods where home defends right (i.e., attacks left).
    def normalize(x:, y:, home_defending_side:)
      if home_defending_side == "right"
        [-x, -y]
      else
        [x, y]
      end
    end

    def to_canvas(nhl_x, nhl_y)
      cx = (nhl_x + 100.0) / NHL_X_RANGE * CANVAS_WIDTH
      cy = (nhl_y + 42.5)  / NHL_Y_RANGE * CANVAS_HEIGHT
      [cx, cy]
    end
  end
end

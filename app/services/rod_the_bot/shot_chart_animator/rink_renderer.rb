require "mini_magick"

module RodTheBot
  class ShotChartAnimator
    module RinkRenderer
      extend self

      W = CoordNormalizer::CANVAS_WIDTH
      H = CoordNormalizer::CANVAS_HEIGHT

      ICE_COLOR     = "#F4F8FB"
      GOAL_LINE     = "#C8102E"
      BLUE_LINE     = "#0033A0"
      CENTER_RED    = "#C8102E"
      FACEOFF_BLUE  = "#0033A0"

      def call(out_path)
        MiniMagick::Tool.new("magick") do |c|
          c.size("#{W}x#{H}")
          c.canvas(ICE_COLOR)
          c.fill("transparent")
          c.stroke(GOAL_LINE)
          c.strokewidth(2)
          # Goal lines (~11ft from each end → x = ±89 → canvas x = 66 and 1134)
          c.draw "line 66,0 66,#{H}"
          c.draw "line 1134,0 1134,#{H}"
          c.stroke(BLUE_LINE)
          c.strokewidth(4)
          # Blue lines (±25ft → canvas x = 450 and 750)
          c.draw "line 450,0 450,#{H}"
          c.draw "line 750,0 750,#{H}"
          c.stroke(CENTER_RED)
          c.strokewidth(2)
          c.draw "line 600,0 600,#{H}"
          # Center circle (15ft radius → 90px)
          c.fill("transparent")
          c.stroke(FACEOFF_BLUE)
          c.strokewidth(2)
          c.draw "circle 600,255 600,165"
          # Faceoff dots/circles in each end (NHL: 20ft from goal line, 22ft from boards)
          [[132, 123], [132, 387], [1068, 123], [1068, 387]].each do |dx, dy|
            c.fill(CENTER_RED)
            c.stroke("transparent")
            c.draw "circle #{dx},#{dy} #{dx + 4},#{dy}"
            c.fill("transparent")
            c.stroke(FACEOFF_BLUE)
            c.draw "circle #{dx},#{dy} #{dx + 90},#{dy}"
          end
          # Goal creases (~6ft semicircle in front of each goal line)
          c.fill("#A0CFEC")
          c.stroke(FACEOFF_BLUE)
          c.strokewidth(1)
          c.draw "circle 66,255 66,219"
          c.draw "circle 1134,255 1134,219"
          c << out_path
        end
      end
    end
  end
end

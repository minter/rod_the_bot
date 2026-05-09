require "mini_magick"
require "tempfile"

module RodTheBot
  class ShotChartAnimator
    module RinkRenderer
      extend self

      W = CoordNormalizer::CANVAS_WIDTH   # 1200
      H = CoordNormalizer::CANVAS_HEIGHT  # 510

      ICE_COLOR    = "#E8F4F8"
      OUTLINE      = "#000000"
      GOAL_LINE    = "#C8102E"
      BLUE_LINE    = "#003DA5"
      CENTER_RED   = "#C8102E"
      FACEOFF_RED  = "#C8102E"
      CENTER_BLUE  = "#003DA5"

      # Rink geometry (pixels, 6px/ft)
      CORNER_R     = 168  # 28ft * 6
      GOAL_X_LEFT  = 66   # 11ft * 6
      GOAL_X_RIGHT = 1134 # (200-11)ft * 6
      CENTER_X     = 600
      CENTER_Y     = 255
      BLUE_LEFT    = 450  # 75ft * 6
      BLUE_RIGHT   = 750  # 125ft * 6
      CREASE_R     = 36   # 6ft * 6
      CIRCLE_R     = 90   # 15ft * 6

      # Faceoff circle centers: 31ft from left/right end, 22ft from top/bottom
      # Left end:  x = 31*6 = 186; Right end: x = (200-31)*6 = 1014
      # Top:       y = 22*6 = 132; Bottom:    y = (85-22)*6 = 378
      FACEOFF_CIRCLES = [
        [186, 132],
        [186, 378],
        [1014, 132],
        [1014, 378]
      ]

      # Goal line clipped y coords (intersection with corner arcs)
      # Corner centers: top-left=(168,168), bottom-left=(168,342)
      # For x=66: horizontal distance from corner center = 168-66 = 102
      # Vertical offset = sqrt(168^2 - 102^2) = sqrt(28224-10404) = sqrt(17820) ≈ 133.5
      GOAL_LINE_INTERSECT_OFFSET = Math.sqrt(CORNER_R**2 - (CORNER_R - GOAL_X_LEFT)**2)
      GOAL_LINE_Y_TOP    = (CORNER_R - GOAL_LINE_INTERSECT_OFFSET).round  # ≈ 35
      GOAL_LINE_Y_BOTTOM = (H - CORNER_R + GOAL_LINE_INTERSECT_OFFSET).round  # ≈ 476

      def call(out_path, home_logo_path: nil, away_logo_path: nil)
        has_logos = home_logo_path || away_logo_path

        if has_logos
          rink_tmp = Tempfile.new(["rink_base", ".png"])
          begin
            draw_base_rink(rink_tmp.path)
            composite_logos(rink_tmp.path, out_path, home_logo_path, away_logo_path)
          ensure
            rink_tmp.close!
          end
        else
          draw_base_rink(out_path)
        end
      end

      private

      def draw_base_rink(target_path)
        MiniMagick::Tool.new("magick") do |c|
          c.size("#{W}x#{H}")
          c.canvas(ICE_COLOR)

          # ── Rink outline (rounded rectangle) ────────────────────────────────
          c.fill("none")
          c.stroke(OUTLINE)
          c.strokewidth(3)
          # roundrectangle x1,y1 x2,y2 rx,ry
          c.draw "roundrectangle 0,0 #{W - 1},#{H - 1} #{CORNER_R},#{CORNER_R}"

          # ── Goal lines (clipped at corner arcs) ──────────────────────────────
          c.stroke(GOAL_LINE)
          c.strokewidth(2)
          c.draw "line #{GOAL_X_LEFT},#{GOAL_LINE_Y_TOP} #{GOAL_X_LEFT},#{GOAL_LINE_Y_BOTTOM}"
          c.draw "line #{GOAL_X_RIGHT},#{GOAL_LINE_Y_TOP} #{GOAL_X_RIGHT},#{GOAL_LINE_Y_BOTTOM}"

          # ── Center red line (8px wide) ───────────────────────────────────────
          c.stroke(CENTER_RED)
          c.strokewidth(8)
          c.draw "line #{CENTER_X},0 #{CENTER_X},#{H}"

          # ── Blue lines (8px wide) ────────────────────────────────────────────
          c.stroke(BLUE_LINE)
          c.strokewidth(8)
          c.draw "line #{BLUE_LEFT},0 #{BLUE_LEFT},#{H}"
          c.draw "line #{BLUE_RIGHT},0 #{BLUE_RIGHT},#{H}"

          # ── Center circle (15ft radius = 90px, blue) ─────────────────────────
          c.fill("none")
          c.stroke(CENTER_BLUE)
          c.strokewidth(2)
          c.draw "circle #{CENTER_X},#{CENTER_Y} #{CENTER_X},#{CENTER_Y - CIRCLE_R}"

          # Center dot
          c.fill(CENTER_BLUE)
          c.stroke("none")
          c.draw "circle #{CENTER_X},#{CENTER_Y} #{CENTER_X + 6},#{CENTER_Y}"

          # ── Faceoff circles (red, 15ft radius) ──────────────────────────────
          FACEOFF_CIRCLES.each do |fx, fy|
            # Circle outline
            c.fill("none")
            c.stroke(FACEOFF_RED)
            c.strokewidth(2)
            c.draw "circle #{fx},#{fy} #{fx},#{fy - CIRCLE_R}"

            # Center dot
            c.fill(FACEOFF_RED)
            c.stroke("none")
            c.draw "circle #{fx},#{fy} #{fx + 6},#{fy}"
          end

          # ── Goal creases (red semicircle, 6ft radius, bulging into center ice) ─
          c.fill("none")
          c.stroke(GOAL_LINE)
          c.strokewidth(2)

          # Left crease: arc from (66, 255-36) to (66, 255+36) sweeping RIGHT into ice
          # SVG arc: M startX,startY A rx,ry x-rot large-arc sweep endX,endY
          # sweep-flag=1 means clockwise; for left goal the bulge is to the right (into ice)
          left_top_y    = CENTER_Y - CREASE_R   # 255 - 36 = 219
          left_bottom_y = CENTER_Y + CREASE_R   # 255 + 36 = 291
          c.draw "path 'M #{GOAL_X_LEFT},#{left_top_y} A #{CREASE_R},#{CREASE_R} 0 0 1 #{GOAL_X_LEFT},#{left_bottom_y}'"

          # Right crease: bulges LEFT into ice (sweep-flag=0 → counter-clockwise)
          right_top_y    = CENTER_Y - CREASE_R
          right_bottom_y = CENTER_Y + CREASE_R
          c.draw "path 'M #{GOAL_X_RIGHT},#{right_top_y} A #{CREASE_R},#{CREASE_R} 0 0 0 #{GOAL_X_RIGHT},#{right_bottom_y}'"

          c << target_path
        end
      end

      def composite_logos(base_path, out_path, home_logo_path, away_logo_path)
        # Home goalie defends LEFT goal (x=66); Away goalie defends RIGHT goal (x=1134).
        # Logo is resized to fit a logo_max x logo_max box, then padded with a
        # transparent canvas to that exact size so the geometry math centers
        # the logo on the goal point regardless of its native aspect ratio.
        # Alpha is multiplied (not "set") so true transparency is preserved
        # and the logo ghosts cleanly into the ice instead of producing a halo.
        logo_max = 120
        alpha_scale = 0.35  # 0.0 = fully transparent, 1.0 = opaque
        home_offset_x = GOAL_X_LEFT - logo_max / 2
        home_offset_y = CENTER_Y - logo_max / 2
        away_offset_x = GOAL_X_RIGHT - logo_max / 2
        away_offset_y = CENTER_Y - logo_max / 2

        MiniMagick::Tool.new("magick") do |c|
          c << base_path

          if home_logo_path
            c.stack do |s|
              s << home_logo_path
              s.resize("#{logo_max}x#{logo_max}")
              s.background("none")
              s.gravity("center")
              s.extent("#{logo_max}x#{logo_max}")
              s.alpha("set")
              s.channel("A")
              s.evaluate("multiply", alpha_scale.to_s)
              s.channel.+  # +channel
            end
            c.gravity("NorthWest")
            c.geometry("+#{home_offset_x}+#{home_offset_y}")
            c.composite
          end

          if away_logo_path
            c.stack do |s|
              s << away_logo_path
              s.resize("#{logo_max}x#{logo_max}")
              s.background("none")
              s.gravity("center")
              s.extent("#{logo_max}x#{logo_max}")
              s.alpha("set")
              s.channel("A")
              s.evaluate("multiply", alpha_scale.to_s)
              s.channel.+  # +channel
            end
            c.gravity("NorthWest")
            c.geometry("+#{away_offset_x}+#{away_offset_y}")
            c.composite
          end

          c << out_path
        end
      end
    end
  end
end

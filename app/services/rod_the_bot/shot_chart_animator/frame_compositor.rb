require "mini_magick"

module RodTheBot
  class ShotChartAnimator
    module FrameCompositor
      extend self

      SHOT_RADIUS = 5
      GOAL_OUTER_R = 18
      GOAL_INNER_R = 8
      GOAL_FILL = "#FFD700"  # gold
      FONT_CANDIDATES = [
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", # Debian/Docker
        "/System/Library/Fonts/Supplemental/Arial.ttf",                   # macOS
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",                # other Linux fallback
      ].freeze
      FONT = FONT_CANDIDATES.find { |p| File.exist?(p) }

      # Composites one animation frame:
      #   - prior shots (from earlier periods) drawn at 70% opacity
      #   - new shots (current period, already revealed) drawn at 100%
      #   - the most-recent new shot may have new_shot_scale applied (pop)
      #   - optional active_caption (timestamp near most-recent shot)
      def compose(rink_path:, out_path:, prior_shots:, new_shots:,
                  new_shot_scale:, active_caption:,
                  away_abbrev:, home_abbrev:, away_color:, home_color:,
                  period_label:, away_sog:, home_sog:)
        raise "No suitable font found. Candidates checked: #{FONT_CANDIDATES.join(', ')}" if FONT.nil?

        MiniMagick::Tool.new("magick") do |c|
          c << rink_path

          # Prior-period shots (70% opacity)
          prior_shots.each do |shot|
            draw_shot(c, shot, scale: 1.0, opacity: 0.7,
                      home_color: home_color, away_color: away_color)
          end

          # New-period shots (100% opacity); last one gets the pop scale
          new_shots.each_with_index do |shot, i|
            scale = (i == new_shots.length - 1) ? new_shot_scale : 1.0
            draw_shot(c, shot, scale: scale, opacity: 1.0,
                      home_color: home_color, away_color: away_color)
          end

          # Active caption near the most-recent shot
          if active_caption && new_shots.any?
            last = new_shots.last
            cx, cy = CoordNormalizer.to_canvas(last[:x], last[:y])
            c.font(FONT)
            c.fill("#000000")
            c.stroke("transparent")
            c.pointsize(18)
            c.draw "text #{cx.to_i + 12},#{cy.to_i - 12} '#{active_caption}'"
          end

          # Period label (bottom-center)
          c.font(FONT)
          c.fill("#000000")
          c.stroke("transparent")
          c.pointsize(28)
          c.gravity("South")
          c.draw "text 0,12 '#{period_label}'"

          # SOG legend (bottom-left)
          c.gravity("SouthWest")
          c.pointsize(20)
          c.draw "text 16,12 '#{away_abbrev} #{away_sog} - #{home_abbrev} #{home_sog}'"
          c.gravity("None")

          c << out_path
        end
      end

      private

      def draw_shot(c, shot, scale:, opacity:, home_color:, away_color:)
        cx, cy = CoordNormalizer.to_canvas(shot[:x], shot[:y])
        team_color = (shot[:team_side] == :home) ? home_color : away_color

        if shot[:type] == "goal"
          outer = GOAL_OUTER_R * scale
          inner = GOAL_INNER_R * scale
          points = star_points(cx, cy, 5, outer, inner)
          c.fill(GOAL_FILL)
          c.stroke(team_color)
          c.strokewidth(3)
          c.draw "polygon #{points}"

          if shot[:goal_number]
            c.font(FONT) if FONT
            c.fill(team_color)
            c.stroke("transparent")
            c.pointsize(14)
            c.gravity("None")
            # rough vertical centering tweak (+5)
            c.draw "text #{cx.to_i - 4},#{cy.to_i + 5} '#{shot[:goal_number]}'"
          end
        else
          radius = SHOT_RADIUS * scale
          fill = "#{team_color}#{opacity_hex(opacity * 0.7)}"
          stroke = "#{team_color}#{opacity_hex(opacity * 0.9)}"
          c.fill(fill)
          c.stroke(stroke)
          c.strokewidth(1)
          c.draw "circle #{cx.to_i},#{cy.to_i} #{(cx + radius).to_i},#{cy.to_i}"
        end
      end

      def opacity_hex(opacity)
        # ImageMagick honors a trailing alpha hex pair, e.g. "#FF000080" = 50%.
        format("%02X", (opacity * 255).round.clamp(0, 255))
      end

      # Returns IM "x,y x,y x,y" string for a 5-point star centered at (cx, cy).
      # Mirrors watch-party-games' drawStar (start at -π/2, alternate outer/inner radius).
      def star_points(cx, cy, points, outer_r, inner_r)
        step = Math::PI / points
        angle = -Math::PI / 2
        coords = []
        (points * 2).times do |i|
          r = i.even? ? outer_r : inner_r
          x = cx + r * Math.cos(angle)
          y = cy + r * Math.sin(angle)
          coords << "#{x.round(1)},#{y.round(1)}"
          angle += step
        end
        coords.join(" ")
      end
    end
  end
end

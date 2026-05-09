require "mini_magick"

module RodTheBot
  class ShotChartAnimator
    module FrameCompositor
      extend self

      SHOT_RADIUS = 7
      GOAL_RADIUS = 11
      FONT        = "/System/Library/Fonts/Supplemental/Arial.ttf"

      # Composites one animation frame:
      #   - prior shots (from earlier periods) drawn at 70% opacity
      #   - new shots (current period, already revealed) drawn at 100%
      #   - the most-recent new shot may have new_shot_scale applied (pop)
      #   - optional active_caption (timestamp near most-recent shot)
      def compose(rink_path:, out_path:, prior_shots:, new_shots:,
                  new_shot_scale:, active_caption:,
                  away_abbrev:, home_abbrev:, away_color:, home_color:,
                  period_label:, away_sog:, home_sog:)
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
        color = (shot[:team_side] == :home) ? home_color : away_color
        radius = (shot[:type] == "goal" ? GOAL_RADIUS : SHOT_RADIUS) * scale

        c.fill("#{color}#{opacity_hex(opacity)}")
        c.stroke(shot[:type] == "goal" ? "white" : "transparent")
        c.strokewidth(shot[:type] == "goal" ? 2 : 0)
        c.draw "circle #{cx.to_i},#{cy.to_i} #{(cx + radius).to_i},#{cy.to_i}"

        if shot[:type] == "goal" && shot[:goal_number]
          c.font(FONT)
          c.fill("white")
          c.stroke("transparent")
          c.pointsize(14)
          c.draw "text #{cx.to_i - 4},#{cy.to_i + 5} '#{shot[:goal_number]}'"
        end
      end

      def opacity_hex(opacity)
        # ImageMagick honors a trailing alpha hex pair, e.g. "#FF000080" = 50%.
        format("%02X", (opacity * 255).round.clamp(0, 255))
      end
    end
  end
end

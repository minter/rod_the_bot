require "fileutils"
require "open3"
require "httparty"

module RodTheBot
  class ShotChartAnimator
    module LogoCache
      extend self

      RASTER_HEIGHT = 240 # px — generous for 1200×510 canvas; scaled down at composite time

      # Returns Pathname to a cached PNG, or nil if fetch/rasterize fails.
      # Safe to call repeatedly with the same args (idempotent).
      def fetch(team_abbrev:, logo_url:)
        return nil if team_abbrev.blank? || logo_url.blank?

        FileUtils.mkdir_p(logo_dir)
        target = logo_dir.join("#{team_abbrev}.png")
        return target if target.exist?

        svg_response = HTTParty.get(logo_url, timeout: 10)
        return nil unless svg_response.success?

        svg_path = logo_dir.join("#{team_abbrev}.svg")
        svg_path.write(svg_response.body)

        out, status = Open3.capture2e(
          "rsvg-convert", "-h", RASTER_HEIGHT.to_s,
          "-o", target.to_s, svg_path.to_s
        )
        unless status.success?
          Rails.logger.warn "LogoCache: rsvg-convert failed for #{team_abbrev}: #{out}"
          File.delete(svg_path) if File.exist?(svg_path)
          File.delete(target) if File.exist?(target)
          return nil
        end

        File.delete(svg_path) if File.exist?(svg_path)
        target
      rescue => e
        Rails.logger.warn "LogoCache: error fetching #{team_abbrev} from #{logo_url}: #{e.class}: #{e.message}"
        nil
      end

      def logo_dir
        Pathname.new(Rails.root.join("tmp", "team_logos"))
      end
    end
  end
end

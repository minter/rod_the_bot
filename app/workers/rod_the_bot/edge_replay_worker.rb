require "open3"
require "json"
require "fileutils"
require "net/http"
require "uri"
require "tmpdir"

module RodTheBot
  class EdgeReplayWorker
    include Sidekiq::Worker

    # Constants from the PoC script
    DEFAULT_RINK_W = 2400.0
    DEFAULT_RINK_H = 1020.0

    TEAM_COLORS = {
      "CAR" => "#cc3333",
      "PHI" => "#f74902"
    }.freeze

    def perform(game_id, event_id)
      Rails.logger.info "EdgeReplayWorker: Generating replay for game #{game_id}, event #{event_id}"

      # Create output directory
      output_dir = Rails.root.join("tmp", "edge_replays")
      FileUtils.mkdir_p(output_dir)

      # Download EDGE JSON
      edge_json_path = download_edge_json(game_id, event_id, output_dir)
      return nil unless edge_json_path

      # Generate MP4
      output_path = output_dir.join("#{game_id}_#{event_id}_replay.mp4")
      generate_replay(edge_json_path, output_path)

      Rails.logger.info "EdgeReplayWorker: Generated replay at #{output_path}"
      output_path.to_s
    rescue => e
      Rails.logger.error "EdgeReplayWorker failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      nil
    end

    private

    def download_edge_json(game_id, event_id, output_dir)
      season_slug = season_slug_from_game_id(game_id)
      url = "https://wsr.nhle.com/sprites/#{season_slug}/#{game_id}/ev#{event_id}.json"

      json_path = output_dir.join("ev#{event_id}.json")

      # Use NHL.com-like headers to avoid Cloudflare blocking
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Get.new(uri.request_uri)
      request["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
      request["Accept"] = "application/json,*/*;q=0.8"
      request["Origin"] = "https://www.nhl.com"
      request["Referer"] = "https://www.nhl.com/gamecenter/#{game_id}/playbyplay"
      request["Sec-Fetch-Site"] = "cross-site"
      request["Sec-Fetch-Mode"] = "cors"
      request["Sec-Fetch-Dest"] = "empty"

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error "Failed to download EDGE JSON from #{url}: HTTP #{response.code}"
        return nil
      end

      File.binwrite(json_path, response.body)
      Rails.logger.info "EdgeReplayWorker: Downloaded EDGE JSON to #{json_path}"
      json_path
    rescue => e
      Rails.logger.error "Error downloading EDGE JSON: #{e.message}"
      nil
    end

    def generate_replay(input_json_path, output_path, options = {})
      options = default_options.merge(options)

      frames = JSON.parse(File.read(input_json_path))
      unless frames.is_a?(Array) && frames.any?
        Rails.logger.error "Invalid EDGE JSON format"
        return nil
      end

      start_idx = [options[:start].to_i, 0].max
      end_idx = options[:frames] ? [start_idx + options[:frames].to_i, frames.length].min : frames.length
      selected = frames[start_idx...end_idx] || []

      if selected.empty?
        Rails.logger.error "No frames to render"
        return nil
      end

      Dir.mktmpdir("edge_replay_") do |tmpdir|
        frames_dir = File.join(tmpdir, "frames")
        FileUtils.mkdir_p(frames_dir)

        render_frames_imagemagick!(selected, options, frames_dir)

        tmp_video = File.join(tmpdir, "video.mp4")
        encode_video(frames_dir, tmp_video, options[:fps])

        FileUtils.mv(tmp_video, output_path)
      end

      output_path
    end

    def render_frames_imagemagick!(selected, options, frames_dir)
      background_path = File.join(frames_dir, "_background.png")
      build_background!(background_path, options)

      w = options[:width].to_i
      h = options[:height].to_i
      tf = rink_transform(options)

      fps = options.fetch(:fps, 30).to_f
      speed = options.fetch(:speed, 1.0).to_f
      speed = 1.0 if speed <= 0
      tick_seconds = options.fetch(:tick_seconds, 0.1).to_f

      # Render base images for each tracking frame
      base_dir = File.join(frames_dir, "_base")
      FileUtils.mkdir_p(base_dir)

      selected.each_with_index do |frame, i|
        on_ice = frame["onIce"] || {}
        entities = on_ice.values.select { |e| e.is_a?(Hash) }
        puck = entities.select { |e| puck_entity?(e) }
        players = entities.reject { |e| puck_entity?(e) }

        out_png = File.join(base_dir, format("base_%05d.png", i))
        cmd = ["magick", background_path]

        # Draw puck first
        puck.each do |ent|
          x = map_x(ent["x"], tf)
          y = map_y(ent["y"], tf)
          r = 6
          cmd += ["-fill", "#111111", "-stroke", "none", "-draw", "circle #{x},#{y} #{(x + r).round(2)},#{y}"]
        end

        # Draw players
        players.each do |ent|
          team = ent["teamAbbrev"].to_s
          fill = TEAM_COLORS.fetch(team, "#444444")
          x = map_x(ent["x"], tf)
          y = map_y(ent["y"], tf)
          r = 18

          cmd += [
            "-stroke", "#ffffff",
            "-strokewidth", "2",
            "-fill", fill,
            "-draw", "circle #{x},#{y} #{(x + r).round(2)},#{y}"
          ]

          num = ent["sweaterNumber"]
          next if num.nil? || num == ""

          dx = (x - (w / 2.0)).round
          dy = (y - (h / 2.0)).round
          cmd += [
            "-gravity", "Center",
            "-fill", "#ffffff",
            "-stroke", "none",
            "-pointsize", "16",
            "-annotate", "#{"+" if dx >= 0}#{dx}#{"+" if dy >= 0}#{dy}", num.to_s
          ]
        end

        cmd << out_png
        run_cmd!(cmd, "ImageMagick frame render #{i}")
      end

      # Build output frame sequence with repeats based on timeStamp deltas
      time_stamps = selected.map { |f| f.is_a?(Hash) ? f["timeStamp"] : nil }.map { |v| v.is_a?(Numeric) ? v.to_i : nil }
      deltas = []
      time_stamps.each_cons(2) do |a, b|
        deltas << ((a && b) ? (b - a) : nil)
      end
      positive = deltas.compact.select { |d| d > 0 }
      fallback_delta = positive.empty? ? 1 : positive.tally.max_by { |_, c| c }[0]

      out_idx = 0
      selected.each_index do |i|
        delta_ticks = if i < deltas.length && deltas[i].is_a?(Integer) && deltas[i] > 0
          deltas[i]
        else
          fallback_delta
        end
        seconds = delta_ticks * tick_seconds
        repeats = [(seconds * fps / speed).round, 1].max
        base_png = File.join(base_dir, format("base_%05d.png", i))

        repeats.times do
          out_png = File.join(frames_dir, format("frame_%05d.png", out_idx))
          FileUtils.cp(base_png, out_png)
          out_idx += 1
        end
      end
    end

    def build_background!(background_path, options)
      w = options[:width].to_i
      h = options[:height].to_i
      tf = rink_transform(options)

      # Get SVG path
      svg_path = Rails.root.join("script", "Icehockeylayout.svg")
      unless File.exist?(svg_path)
        raise "SVG rink template not found at: #{svg_path}"
      end

      # SVG ice surface coordinates
      # These represent the actual ice surface in the SVG coordinate system
      # EDGE coordinates (0,0) to (2400, 1020) map to this ice surface
      svg_ice_surface_x = 27.64
      svg_ice_surface_y = 27.09
      svg_ice_surface_width = 690.18
      svg_ice_surface_height = 293.32

      # ViewBox for rendering (includes boards for rounded corners)
      svg_padding = 15.6
      svg_render_x = svg_ice_surface_x - svg_padding
      svg_render_y = svg_ice_surface_y - svg_padding
      svg_render_width = svg_ice_surface_width + (svg_padding * 2)
      svg_render_height = svg_ice_surface_height + (svg_padding * 2)

      # Canvas pixel dimensions for the EDGE rink (0-2400, 0-1020)
      rink_width_px = (tf[:x1] - tf[:x0]).round
      rink_height_px = (tf[:y1] - tf[:y0]).round

      # Calculate the scale factor from SVG ice surface to canvas pixels
      # This ensures the SVG ice surface matches the EDGE rink size on canvas
      svg_to_canvas_scale_x = rink_width_px.to_f / svg_ice_surface_width
      svg_to_canvas_scale_y = rink_height_px.to_f / svg_ice_surface_height

      # Render the SVG (with padding) at the correct size
      # The rendered PNG will be larger than the ice surface due to padding
      render_width_px = (svg_render_width * svg_to_canvas_scale_x).round
      render_height_px = (svg_render_height * svg_to_canvas_scale_y).round

      # Convert SVG to PNG
      tmp_rink_png = File.join(File.dirname(background_path), "_rink_only.png")
      tmp_svg = File.join(File.dirname(background_path), "_rink_cropped.svg")

      svg_content = File.read(svg_path)
      svg_content = svg_content.sub(
        /viewBox="[^"]*"/,
        "viewBox=\"#{svg_render_x.round(2)} #{svg_render_y.round(2)} #{svg_render_width.round(2)} #{svg_render_height.round(2)}\""
      )
      File.write(tmp_svg, svg_content)

      run_cmd!(
        ["rsvg-convert", "-w", render_width_px.to_s, "-h", render_height_px.to_s, "-o", tmp_rink_png, tmp_svg],
        "Convert SVG to PNG"
      )

      # Calculate where to position the rendered PNG on the canvas
      # The ice surface portion of the PNG must align with tf[:x0], tf[:y0]
      # The padding in the rendered PNG is at the edges
      padding_px_x = (svg_padding * svg_to_canvas_scale_x).round
      padding_px_y = (svg_padding * svg_to_canvas_scale_y).round

      # Position the PNG so the ice surface corner aligns with the EDGE rink corner
      png_x = tf[:x0].round - padding_px_x
      png_y = tf[:y0].round - padding_px_y

      # Composite onto canvas
      run_cmd!(
        ["magick", "-size", "#{w}x#{h}", "xc:#0b0f14", tmp_rink_png, "-geometry", "+#{png_x}+#{png_y}", "-composite", background_path],
        "Composite rink onto canvas"
      )
    end

    def encode_video(frames_dir, output_path, fps)
      run_cmd!(
        [
          "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
          "-framerate", fps.to_s,
          "-i", File.join(frames_dir, "frame_%05d.png"),
          "-c:v", "libx264",
          "-pix_fmt", "yuv420p",
          "-movflags", "+faststart",
          "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
          output_path
        ],
        "ffmpeg encode"
      )
    end

    # Helper methods from script

    def season_slug_from_game_id(game_id)
      s = game_id.to_s.strip
      raise "Invalid game_id" unless s.match?(/\A\d{10}\z/)

      year = s[0, 4].to_i
      "#{year}#{year + 1}"
    end

    def puck_entity?(ent)
      pid = ent["playerId"]
      team = ent["teamAbbrev"]
      (pid.nil? || pid == "") && (team.nil? || team == "")
    end

    def rink_transform(options)
      w = options[:width].to_f
      h = options[:height].to_f
      rink_w = options[:rink_w].to_f
      rink_h = options[:rink_h].to_f
      pad = options.fetch(:pad, 14).to_f

      avail_w = [w - (2.0 * pad), 1.0].max
      avail_h = [h - (2.0 * pad), 1.0].max
      scale = [avail_w / rink_w, avail_h / rink_h].min

      drawn_w = rink_w * scale
      drawn_h = rink_h * scale
      x0 = ((w - drawn_w) / 2.0).round(2)
      y0 = ((h - drawn_h) / 2.0).round(2)

      {
        scale: scale,
        x0: x0,
        y0: y0,
        x1: (x0 + drawn_w).round(2),
        y1: (y0 + drawn_h).round(2),
        rink_w: rink_w,
        rink_h: rink_h
      }
    end

    def map_x(x, tf)
      (tf[:x0] + (x.to_f * tf[:scale])).round(2)
    end

    def map_y(y, tf)
      (tf[:y0] + (y.to_f * tf[:scale])).round(2)
    end

    def default_options
      {
        width: 1280,
        height: 720,
        fps: 30,
        speed: 1.0,
        tick_seconds: 0.1,
        rink_w: DEFAULT_RINK_W,
        rink_h: DEFAULT_RINK_H,
        start: 0,
        frames: nil
      }
    end

    def run_cmd!(cmd, label)
      stdout, status = Open3.capture2e(*cmd)
      return if status.success?

      raise "#{label} failed:\n#{stdout}"
    end
  end
end

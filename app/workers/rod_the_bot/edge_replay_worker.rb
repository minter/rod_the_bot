require "open3"
require "json"
require "fileutils"
require "net/http"
require "uri"
require "tmpdir"

module RodTheBot
  class EdgeReplayWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector
    include RodTheBot::PeriodFormatter
    include RodTheBot::PlayerFormatter

    # Constants from the PoC script
    DEFAULT_RINK_W = 2400.0
    DEFAULT_RINK_H = 1020.0

    # NHL team primary colors (hex codes)
    TEAM_COLORS = {
      "ANA" => "#B9975B", "ARI" => "#8C2633", "BOS" => "#FFB81C", "BUF" => "#003E7E",
      "CGY" => "#C8102E", "CAR" => "#CC0000", "CHI" => "#C8102E", "COL" => "#6F263D",
      "CBJ" => "#002654", "DAL" => "#006847", "DET" => "#CE1126", "EDM" => "#FF4C00",
      "FLA" => "#C8102E", "LAK" => "#111111", "MIN" => "#154734", "MTL" => "#AF1E2D",
      "NSH" => "#FFB81C", "NJD" => "#CE1126", "NYI" => "#00539B", "NYR" => "#0038A8",
      "OTT" => "#C8102E", "PHI" => "#F74902", "PIT" => "#000000", "SJS" => "#006D75",
      "SEA" => "#001628", "STL" => "#002F87", "TBL" => "#002868", "TOR" => "#00205B",
      "VAN" => "#00205B", "VGK" => "#B4975A", "WSH" => "#C8102E", "WPG" => "#041E42"
    }.freeze

    def perform(game_id, event_id, redis_key = nil, retry_count = 0)
      Rails.logger.info "EdgeReplayWorker: Generating replay for game #{game_id}, event #{event_id} (attempt #{retry_count + 1})"

      # Create output directory
      output_dir = Rails.root.join("tmp", "edge_replays")
      FileUtils.mkdir_p(output_dir)

      # Check if replay already exists
      output_path = output_dir.join("#{game_id}_#{event_id}_replay.mp4")
      if output_path.exist?
        Rails.logger.info "EdgeReplayWorker: Replay already exists at #{output_path}, skipping generation"
        # If redis_key provided, post the existing replay
        if redis_key
          post_edge_replay(game_id, event_id, output_path.to_s, redis_key)
        end
        return output_path.to_s
      end

      # Download EDGE JSON
      edge_json_path = download_edge_json(game_id, event_id, output_dir)
      unless edge_json_path
        Rails.logger.warn "EdgeReplayWorker: EDGE JSON not available for game #{game_id}, event #{event_id}"
        # Retry if redis_key provided (meaning we want to post it)
        if redis_key && retry_count < 5 # Limit retries to prevent infinite loops
          Rails.logger.info "EdgeReplayWorker: Re-enqueuing in 90 seconds (retry #{retry_count + 1}/5)"
          self.class.perform_in(90.seconds, game_id, event_id, redis_key, retry_count + 1)
        end
        return nil
      end

      # Fetch game data to determine home/away teams and get logos
      game_data = fetch_game_data(game_id)
      unless game_data
        Rails.logger.warn "EdgeReplayWorker: Game data not available for game #{game_id}"
        # Retry if redis_key provided
        if redis_key && retry_count < 5
          Rails.logger.info "EdgeReplayWorker: Re-enqueuing in 90 seconds (retry #{retry_count + 1}/5)"
          self.class.perform_in(90.seconds, game_id, event_id, redis_key, retry_count + 1)
        end
        return nil
      end

      # Generate MP4
      generate_replay(edge_json_path, output_path, game_data: game_data)

      Rails.logger.info "EdgeReplayWorker: Generated replay at #{output_path}"

      # Post the replay if redis_key provided
      if redis_key
        post_edge_replay(game_id, event_id, output_path.to_s, redis_key)
      end

      output_path.to_s
    rescue => e
      Rails.logger.error "EdgeReplayWorker failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      # Retry on error if redis_key provided
      if redis_key && retry_count < 5
        Rails.logger.info "EdgeReplayWorker: Re-enqueuing after error in 90 seconds (retry #{retry_count + 1}/5)"
        self.class.perform_in(90.seconds, game_id, event_id, redis_key, retry_count + 1)
      end
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

        render_frames_imagemagick!(selected, options, frames_dir, tmpdir)

        tmp_video = File.join(tmpdir, "video.mp4")
        encode_video(frames_dir, tmp_video, options[:fps])

        FileUtils.mv(tmp_video, output_path)
      end

      output_path
    end

    def render_frames_imagemagick!(selected, options, frames_dir, tmpdir)
      background_path = File.join(frames_dir, "_background.png")
      game_data = options[:game_data] || {}
      build_background!(background_path, options, game_data, tmpdir)

      w = options[:width].to_i
      h = options[:height].to_i
      tf = rink_transform(options)

      # Determine home team ID from game data
      home_team_id = game_data.dig("homeTeam", "id")

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
          team_abbrev = ent["teamAbbrev"].to_s
          team_id = ent["teamId"]
          is_home = team_id == home_team_id
          primary_color = TEAM_COLORS.fetch(team_abbrev, "#444444")

          x = map_x(ent["x"], tf)
          y = map_y(ent["y"], tf)
          r = 24

          if is_home
            # Home team: solid primary color circle with white numbers
            cmd += [
              "-stroke", "none",
              "-fill", primary_color,
              "-draw", "circle #{x},#{y} #{(x + r).round(2)},#{y}"
            ]
            number_color = "#ffffff"
          else
            # Away team: white circle with primary color outline and primary color numbers
            cmd += [
              "-stroke", primary_color,
              "-strokewidth", "2",
              "-fill", "#ffffff",
              "-draw", "circle #{x},#{y} #{(x + r).round(2)},#{y}"
            ]
            number_color = primary_color
          end

          num = ent["sweaterNumber"]
          next if num.nil? || num == ""

          dx = (x - (w / 2.0)).round
          dy = (y - (h / 2.0)).round
          cmd += [
            "-gravity", "Center",
            "-fill", number_color,
            "-stroke", "none",
            "-pointsize", "20",
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

    def build_background!(background_path, options, game_data, tmpdir)
      w = options[:width].to_i
      h = options[:height].to_i
      tf = rink_transform(options)

      # Get SVG path
      svg_path = Rails.root.join("config", "rink", "Icehockeylayout.svg")
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

      # Composite rink onto canvas
      cmd = [
        "magick", "-size", "#{w}x#{h}", "xc:#0b0f14",
        tmp_rink_png, "-geometry", "+#{png_x}+#{png_y}", "-composite"
      ]

      # Add home team logo overlay at center ice if available
      home_team_logo_path = download_team_logo(game_data.dig("homeTeam", "logo"), tmpdir) if game_data.dig("homeTeam", "logo")
      if home_team_logo_path && File.exist?(home_team_logo_path)
        # Center ice position in EDGE coordinates: (1200, 510)
        center_x = map_x(1200, tf)
        center_y = map_y(510, tf)
        # Center ice circle is 15 feet radius = 180 EDGE units radius = 360 EDGE units diameter
        # Logo size: fill the center circle (use ~95% of circle diameter)
        logo_size = (340 * tf[:scale]).round
        logo_x = (center_x - logo_size / 2).round
        logo_y = (center_y - logo_size / 2).round

        # Convert SVG to PNG and make it semi-transparent (ghosted effect)
        tmp_logo_png = File.join(tmpdir, "_logo.png")
        tmp_logo_resized = File.join(tmpdir, "_logo_resized.png")

        # Convert SVG to PNG first
        run_cmd!(
          ["rsvg-convert", "-w", logo_size.to_s, "-h", logo_size.to_s, "-o", tmp_logo_png, home_team_logo_path],
          "Convert logo SVG to PNG"
        )

        # Apply transparency (ghosted effect - 15% opacity)
        run_cmd!(
          ["magick", tmp_logo_png, "-alpha", "set", "-channel", "A", "-evaluate", "multiply", "0.15", "+channel", tmp_logo_resized],
          "Apply ghosted effect to logo"
        )

        cmd += [tmp_logo_resized, "-geometry", "+#{logo_x}+#{logo_y}", "-composite"]
      end

      cmd << background_path
      run_cmd!(cmd, "Composite rink and logo onto canvas")
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

    def fetch_game_data(game_id)
      game_data = NhlApi.fetch_landing_feed(game_id)
      return nil unless game_data && game_data["homeTeam"] && game_data["awayTeam"]

      game_data
    rescue => e
      Rails.logger.error "Error fetching game data: #{e.message}"
      nil
    end

    def download_team_logo(logo_url, tmpdir)
      return nil unless logo_url

      # Extract team abbreviation from URL (e.g., "PHI_light.svg" -> "PHI")
      team_abbrev = logo_url.match(%r{/([A-Z]+)_})&.[](1)
      return nil unless team_abbrev

      logo_path = File.join(tmpdir, "#{team_abbrev}_logo.svg")

      # Download logo if not already cached
      unless File.exist?(logo_path)
        uri = URI.parse(logo_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Get.new(uri.request_uri)
        request["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"

        response = http.request(request)

        if response.is_a?(Net::HTTPSuccess)
          File.binwrite(logo_path, response.body)
          Rails.logger.info "Downloaded team logo: #{logo_url}"
        else
          Rails.logger.error "Failed to download logo from #{logo_url}: HTTP #{response.code}"
          return nil
        end
      end

      logo_path
    rescue => e
      Rails.logger.error "Error downloading team logo: #{e.message}"
      nil
    end

    def post_edge_replay(game_id, event_id, video_path, redis_key)
      # Fetch play data to format post text
      pbp_feed = NhlApi.fetch_pbp_feed(game_id)
      pbp_play = NhlApi.fetch_play(game_id, event_id)
      return unless pbp_play && pbp_play["typeDescKey"] == "goal"

      # Get roster data
      players = NhlApi.game_rosters(game_id)

      # Format post text
      post_text = format_edge_replay_post(pbp_play, players, pbp_feed)

      # Create a unique key for this EDGE replay post
      edge_replay_key = "#{redis_key}:edge_replay:#{Time.now.to_i}"

      # Determine parent_key: Use most recent reply if it exists, otherwise use goal post (root)
      # Threading: Goal (root) -> most recent reply -> next reply -> etc.
      # The Post worker will atomically update last_reply_key after successful posting
      last_reply_tracker_key = "#{redis_key}:last_reply_key"
      last_reply_key = REDIS.get(last_reply_tracker_key)

      # Use last reply as parent if it exists, otherwise use root (goal post)
      parent_key = last_reply_key || redis_key

      if last_reply_key
        Rails.logger.info "EdgeReplayWorker: Replying to most recent reply with key: #{parent_key}"
      else
        Rails.logger.info "EdgeReplayWorker: No previous replies, replying to goal post (root) with key: #{parent_key}"
      end

      # Post as reply - Post worker will update last_reply_key after successful post
      RodTheBot::Post.perform_async(post_text, edge_replay_key, parent_key, nil, [], video_path, redis_key)
    end

    def format_edge_replay_post(play, players, feed)
      # Format scorer with jersey number
      scorer_id = play.dig("details", "scoringPlayerId")
      scorer_name = if scorer_id
        format_player_from_roster(players, scorer_id)
      else
        "Unknown Player"
      end

      team_abbrev = play.dig("details", "eventOwnerTeamId")
      scoring_team = if feed["homeTeam"]["id"] == team_abbrev
        feed["homeTeam"]["abbrev"]
      else
        feed["awayTeam"]["abbrev"]
      end

      time = play["timeInPeriod"]
      period_name = format_period_name(play["periodDescriptor"]["number"])

      # Format assists with jersey numbers
      assist_names = []
      if play.dig("details", "assist1PlayerId").present?
        assist_names << format_player_from_roster(players, play.dig("details", "assist1PlayerId"))
      end
      if play.dig("details", "assist2PlayerId").present?
        assist_names << format_player_from_roster(players, play.dig("details", "assist2PlayerId"))
      end

      assist_text = assist_names.empty? ? "" : " Assisted by #{assist_names.join(", ")}."

      away_team = feed["awayTeam"]["abbrev"]
      home_team = feed["homeTeam"]["abbrev"]
      away_score = play.dig("details", "awayScore") || 0
      home_score = play.dig("details", "homeScore") || 0
      score = format("%s %d - %s %d", away_team, away_score, home_team, home_score)

      "📊 EDGE replay: #{scorer_name} (#{scoring_team}) scores at #{time} of the #{period_name}." \
      "#{assist_text} Score: #{score}"
    end

    def run_cmd!(cmd, label)
      stdout, status = Open3.capture2e(*cmd)
      return if status.success?

      raise "#{label} failed:\n#{stdout}"
    end
  end
end

require "mini_magick"
require "fileutils"
require "tmpdir"
require "open3"

module RodTheBot
  class ShotChartAnimator
    # ImageMagick 7 ships a unified `magick` binary; ImageMagick 6 ships only
    # `convert`/`mogrify`/etc. Detect at load time so we can run on either
    # (Docker prod has IM7; the CI runner has IM6).
    IM_BINARY = (system("which magick > /dev/null 2>&1") ? "magick" : "convert").freeze

    INTRO_SECONDS = 1.0
    OUTRO_SECONDS = 3.0
    POP_SECONDS = 0.3
    POP_FRAMES = 4
    TOTAL_BUDGET = 50.0
    FRAME_FPS = 30
    MAX_VIDEO_BYTES = 50 * 1024 * 1024
    MAX_VIDEO_SECS = 60

    TEAM_COLORS = {
      "ANA" => "#F47A38", "ARI" => "#8C2633", "BOS" => "#FFB81C", "BUF" => "#003087",
      "CGY" => "#D2001C", "CAR" => "#CC0000", "CHI" => "#CF0A2C", "COL" => "#6F263D",
      "CBJ" => "#002654", "DAL" => "#006847", "DET" => "#CE1126", "EDM" => "#FF4C00",
      "FLA" => "#C8102E", "LAK" => "#000000", "MIN" => "#154734", "MTL" => "#AF1E2D",
      "NSH" => "#FFB81C", "NJD" => "#CE1126", "NYI" => "#00539B", "NYR" => "#0038A8",
      "OTT" => "#C8102E", "PHI" => "#F74902", "PIT" => "#FCB514", "SJS" => "#006D75",
      "SEA" => "#001628", "STL" => "#002F87", "TBL" => "#002868", "TOR" => "#00205B",
      "UTA" => "#71AFE5", "VAN" => "#00205B", "VGK" => "#B4975A", "WSH" => "#C8102E",
      "WPG" => "#041E42"
    }.freeze

    DEFAULT_COLOR = "#444444"

    PERIOD_LABELS = {1 => "End of 1st", 2 => "End of 2nd", 3 => "End of 3rd", 4 => "End of OT"}.freeze

    def initialize(game_id:, through_period:)
      @game_id = game_id
      @through_period = through_period
    end

    def call
      return Pathname.new("test/fixtures/files/test_shot_chart.mp4") if Rails.env.test?

      target = output_path
      return target if target.exist?

      feed = NhlApi.fetch_pbp_feed(@game_id)
      shots = ShotExtractor.call(feed: feed, through_period: @through_period)
      return nil if shots.empty?

      home = feed["homeTeam"]
      away = feed["awayTeam"]
      home_color = TEAM_COLORS[home["abbrev"]] || DEFAULT_COLOR
      away_color = TEAM_COLORS[away["abbrev"]] || DEFAULT_COLOR
      home_logo = LogoCache.fetch(team_abbrev: home["abbrev"], logo_url: home["logo"])
      away_logo = LogoCache.fetch(team_abbrev: away["abbrev"], logo_url: away["logo"])

      prior, current = shots.partition { |s| s[:period] < @through_period }
      annotate_goal_numbers!(shots)

      frame_dir = output_dir.join("p#{@through_period}_frames")
      FileUtils.mkdir_p(frame_dir)

      rink_path = frame_dir.join("rink.png").to_s
      RinkRenderer.call(rink_path, home_logo_path: home_logo&.to_s, away_logo_path: away_logo&.to_s)

      sog_progression = compute_sog_progression(prior, current, home["id"], away["id"])
      concat_lines = []

      intro_path = render_frame(rink_path, frame_dir.join("intro.png").to_s,
        prior_shots: prior, new_shots: [], new_shot_scale: 1.0,
        active_caption: nil,
        away_abbrev: away["abbrev"], home_abbrev: home["abbrev"],
        away_color: away_color, home_color: home_color,
        period_label: period_label,
        away_sog: sog_progression[:start_away],
        home_sog: sog_progression[:start_home])
      concat_lines << format_concat(intro_path, INTRO_SECONDS)

      revealed = []
      dwell = compute_dwell(current.size)

      current.each_with_index do |shot, i|
        revealed << shot
        sog = sog_progression[:after_each][i]

        POP_FRAMES.times do |k|
          scale = pop_scale(k)
          path = frame_dir.join("shot_#{i}_pop_#{k}.png").to_s
          render_frame(rink_path, path,
            prior_shots: prior, new_shots: revealed, new_shot_scale: scale,
            active_caption: shot[:time_in_period],
            away_abbrev: away["abbrev"], home_abbrev: home["abbrev"],
            away_color: away_color, home_color: home_color,
            period_label: period_label,
            away_sog: sog[:away], home_sog: sog[:home])
          concat_lines << format_concat(path, POP_SECONDS / POP_FRAMES)
        end

        path = frame_dir.join("shot_#{i}_settled.png").to_s
        render_frame(rink_path, path,
          prior_shots: prior, new_shots: revealed, new_shot_scale: 1.0,
          active_caption: nil,
          away_abbrev: away["abbrev"], home_abbrev: home["abbrev"],
          away_color: away_color, home_color: home_color,
          period_label: period_label,
          away_sog: sog[:away], home_sog: sog[:home])
        concat_lines << format_concat(path, dwell)
      end

      outro_path = frame_dir.join("outro.png").to_s
      render_frame(rink_path, outro_path,
        prior_shots: prior, new_shots: current, new_shot_scale: 1.0,
        active_caption: nil,
        away_abbrev: away["abbrev"], home_abbrev: home["abbrev"],
        away_color: away_color, home_color: home_color,
        period_label: period_label,
        away_sog: sog_progression[:after_each].last&.dig(:away) || sog_progression[:start_away],
        home_sog: sog_progression[:after_each].last&.dig(:home) || sog_progression[:start_home])
      concat_lines << format_concat(outro_path, OUTRO_SECONDS)

      concat_file = frame_dir.join("concat.txt")
      concat_file.write(concat_lines.join("\n") + "\n")

      begin
        stitch(concat_file, target)
      ensure
        cleanup_frames(frame_dir, target)
      end

      enforce_size_limit(target)
    rescue NhlApi::APIError => e
      Rails.logger.error "ShotChartAnimator: API error for game #{@game_id}: #{e.message}"
      nil
    end

    private

    def output_dir
      Pathname.new(Rails.root.join("tmp", "shot_charts", @game_id.to_s))
    end

    def output_path
      output_dir.tap { |d| FileUtils.mkdir_p(d) }.join("p#{@through_period}.mp4")
    end

    def period_label
      PERIOD_LABELS[@through_period] || "End of P#{@through_period}"
    end

    def render_frame(rink_path, out_path, **kwargs)
      FrameCompositor.compose(rink_path: rink_path, out_path: out_path, **kwargs)
      out_path
    end

    def annotate_goal_numbers!(shots)
      counts = Hash.new(0)
      shots.each do |s|
        if s[:type] == "goal"
          counts[s[:team_side]] += 1
          s[:goal_number] = counts[s[:team_side]]
        end
      end
    end

    def compute_sog_progression(prior, current, home_id, away_id)
      start_away = prior.count { |s| s[:team_id] == away_id }
      start_home = prior.count { |s| s[:team_id] == home_id }
      after = []
      a, h = start_away, start_home
      current.each do |s|
        a += 1 if s[:team_id] == away_id
        h += 1 if s[:team_id] == home_id
        after << {away: a, home: h}
      end
      {start_away: start_away, start_home: start_home, after_each: after}
    end

    def compute_dwell(n)
      return 0 if n.zero?
      remaining = TOTAL_BUDGET - INTRO_SECONDS - OUTRO_SECONDS - (POP_SECONDS * n)
      [remaining / n, 0.4].max
    end

    def pop_scale(frame_index)
      [0.6, 1.3, 1.1, 1.0][frame_index]
    end

    def format_concat(path, duration)
      "file '#{path}'\nduration #{format("%.3f", duration)}"
    end

    def stitch(concat_file, target)
      cmd = [
        "ffmpeg", "-y", "-f", "concat", "-safe", "0",
        "-i", concat_file.to_s,
        "-vf", "fps=#{FRAME_FPS},format=yuv420p",
        "-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p",
        target.to_s
      ]
      out, status = Open3.capture2e(*cmd)
      raise "ffmpeg failed (exit #{status.exitstatus}): #{out}" unless status.success?
    end

    def cleanup_frames(frame_dir, kept_mp4)
      Dir.glob(frame_dir.join("*.png")).each { |f| File.delete(f) }
      File.delete(frame_dir.join("concat.txt").to_s) if File.exist?(frame_dir.join("concat.txt").to_s)
    end

    def enforce_size_limit(target)
      size = File.size(target)
      duration = begin
        FFMPEG::Movie.new(target.to_s).duration
      rescue
        nil
      end
      if size > MAX_VIDEO_BYTES || (duration && duration > MAX_VIDEO_SECS)
        Rails.logger.warn "ShotChartAnimator: rendered video exceeds limits " \
                          "(size=#{size}, dur=#{duration}). Skipping."
        File.delete(target)
        return nil
      end
      target
    end
  end
end

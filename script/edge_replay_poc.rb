#!/usr/bin/env ruby
# frozen_string_literal: true

# Proof of concept: render NHL EDGE tracking frames (evNNN.json) into a simple
# top-down goal replay MP4 suitable for posting to Bluesky.
#
# Default renderer: ImageMagick (NO Chrome/Chromedriver needed).
#
# Example:
#   zsh -i -c "bundle exec ruby script/edge_replay_poc.rb --input tmp/edge/ev189.json --out tmp/edge/ev189_poc.mp4 --fps 30"
#
# Fetch + render example (gameId + eventId):
#   zsh -i -c "bundle exec ruby script/edge_replay_poc.rb --game-id 2025020501 --event 544 --out tmp/edge/ev544_poc.mp4"
#
# Optional (kept for reference): render via headless Chrome:
#   zsh -i -c "bundle exec ruby script/edge_replay_poc.rb --renderer chrome --input tmp/edge/ev189.json --out tmp/edge/ev189_poc.mp4"

require "json"
require "fileutils"
require "optparse"
require "securerandom"
require "tmpdir"
require "open3"
require "net/http"
require "uri"

DEFAULT_RINK_W = 2400.0
DEFAULT_RINK_H = 1020.0

TEAM_COLORS = {
  "CAR" => "#cc3333",
  "PHI" => "#f74902"
}.freeze

def run_cmd!(cmd, label:)
  stdout, status = Open3.capture2e(*cmd)
  return if status.success?
  raise "#{label} failed:\n#{stdout}"
end

def season_slug_from_game_id(game_id)
  s = game_id.to_s.strip
  unless s.match?(/\A\d{10}\z/)
    raise "Invalid --game-id (expected 10 digits like 2025020501): #{game_id.inspect}"
  end

  year = s[0, 4].to_i
  "#{year}#{year + 1}"
end

def fetch_edge_event_json!(game_id:, event_id:, season_slug: nil, game_url: nil, user_agent: nil, out_json_path:, out_headers_path: nil)
  season_slug ||= season_slug_from_game_id(game_id)
  event_id = event_id.to_i
  raise "Invalid --event (must be positive integer)" if event_id <= 0

  url = "https://wsr.nhle.com/sprites/#{season_slug}/#{game_id}/ev#{event_id}.json"
  origin = "https://www.nhl.com"
  referer = game_url.to_s.strip
  referer = "https://www.nhl.com/gamecenter/#{game_id}/playbyplay" if referer.empty?
  ua = user_agent.to_s.strip
  ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" if ua.empty?

  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == "https")

  req = Net::HTTP::Get.new(uri.request_uri)
  req["User-Agent"] = ua
  req["Accept"] = "application/json,*/*;q=0.8"
  req["Origin"] = origin
  req["Referer"] = referer
  req["Sec-Fetch-Site"] = "cross-site"
  req["Sec-Fetch-Mode"] = "cors"
  req["Sec-Fetch-Dest"] = "empty"

  res = http.request(req)
  unless res.is_a?(Net::HTTPSuccess)
    body_preview = res.body.to_s[0, 400]
    raise "Failed to fetch EDGE event JSON (HTTP #{res.code}) from #{url}\n#{body_preview}"
  end

  FileUtils.mkdir_p(File.dirname(out_json_path))
  File.binwrite(out_json_path, res.body.to_s)

  if out_headers_path
    FileUtils.mkdir_p(File.dirname(out_headers_path))
    headers = +"HTTP #{res.code}\n"
    res.each_header { |k, v| headers << "#{k}: #{v}\n" }
    File.write(out_headers_path, headers)
  end

  {
    url: url,
    json_path: out_json_path,
    bytes: res.body.to_s.bytesize
  }
end

def puck_entity?(ent)
  pid = ent["playerId"]
  team = ent["teamAbbrev"]
  (pid.nil? || pid == "") && (team.nil? || team == "")
end

def rink_transform(options)
  # Compute a single uniform scale + offset so that rink units map into the
  # canvas consistently for BOTH background and entities.
  #
  # By default NHL EDGE payloads use rink_w=2400, rink_h=1020, which matches
  # 200' x 85' at 12 units / foot (uniform).
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

def build_background!(background_path, options)
  w = options[:width].to_i
  h = options[:height].to_i

  # Compute the mapping in EDGE rink units for proper entity positioning
  tf = rink_transform(options)

  # Get the directory where this script lives (to find the SVG)
  script_dir = File.dirname(File.expand_path(__FILE__))
  svg_path = File.join(script_dir, "Icehockeylayout.svg")

  unless File.exist?(svg_path)
    raise "SVG rink template not found at: #{svg_path}"
  end

  # The SVG has viewBox="0 0 748.498 347.5" and the ice surface occupies:
  # - SVG coordinates: X: 27.64 to 717.82, Y: 27.09 to 320.41
  # - This represents the regulation 200' x 85' ice surface
  # - EDGE coordinates: (0,0) to (2400, 1020) map to this ice surface
  #
  # To show rounded board corners, we render a slightly larger area of the SVG,
  # but we must account for this when mapping EDGE coordinates.
  
  # The actual ice surface in SVG units
  svg_ice_surface_x = 27.64
  svg_ice_surface_y = 27.09
  svg_ice_surface_width = 690.18
  svg_ice_surface_height = 293.32
  
  # ViewBox for rendering (includes boards for rounded corners)
  # We add padding around the ice surface to show the board curves
  svg_padding = 15.6  # Padding in SVG units to show boards
  svg_render_x = svg_ice_surface_x - svg_padding
  svg_render_y = svg_ice_surface_y - svg_padding  
  svg_render_width = svg_ice_surface_width + (svg_padding * 2)
  svg_render_height = svg_ice_surface_height + (svg_padding * 2)
  
  # Calculate the size we need to render the SVG (including padding for boards)
  # The rink_transform tells us where the ice surface should fit on the canvas
  rink_width_px = (tf[:x1] - tf[:x0]).round
  rink_height_px = (tf[:y1] - tf[:y0]).round
  
  # Calculate how much bigger the rendered SVG needs to be to include the padding
  # Padding is svg_padding on each side, so total render size is proportionally larger
  padding_scale_x = svg_render_width / svg_ice_surface_width
  padding_scale_y = svg_render_height / svg_ice_surface_height
  
  render_width_px = (rink_width_px * padding_scale_x).round
  render_height_px = (rink_height_px * padding_scale_y).round

  # Step 1: Convert SVG to PNG with the viewBox that includes boards
  tmp_rink_png = File.join(File.dirname(background_path), "_rink_only.png")
  
  # Create a modified SVG with adjusted viewBox to show ice + boards
  tmp_svg = File.join(File.dirname(background_path), "_rink_cropped.svg")
  svg_content = File.read(svg_path)
  svg_content = svg_content.sub(
    /viewBox="[^"]*"/,
    "viewBox=\"#{svg_render_x.round(2)} #{svg_render_y.round(2)} #{svg_render_width.round(2)} #{svg_render_height.round(2)}\""
  )
  File.write(tmp_svg, svg_content)
  
  # Convert the cropped SVG to PNG
  svg_to_png_cmd = [
    "rsvg-convert",
    "-w", render_width_px.to_s,
    "-h", render_height_px.to_s,
    "-o", tmp_rink_png,
    tmp_svg
  ]
  run_cmd!(svg_to_png_cmd, label: "Convert SVG to PNG")

  # Step 2: Calculate where to position the rendered PNG on the canvas
  # The ice surface should be at (tf[:x0], tf[:y0]), but the PNG includes padding
  # So we need to offset by the padding amount
  padding_px_x = (rink_width_px * (svg_padding / svg_ice_surface_width)).round
  padding_px_y = (rink_height_px * (svg_padding / svg_ice_surface_height)).round
  
  png_x = tf[:x0].round - padding_px_x
  png_y = tf[:y0].round - padding_px_y

  # Step 3: Create canvas with PNG composite
  cmd = [
    "magick",
    "-size", "#{w}x#{h}",
    "xc:#0b0f14",
    tmp_rink_png,
    "-geometry", "+#{png_x}+#{png_y}",
    "-composite",
    background_path
  ]

  run_cmd!(cmd, label: "Composite rink onto canvas")
end

def render_frames_imagemagick!(selected, options, frames_dir)
  run_cmd!(["magick", "-version"], label: "ImageMagick presence check")

  background_path = File.join(frames_dir, "_background.png")
  build_background!(background_path, options)

  w = options[:width].to_i
  h = options[:height].to_i
  tf = rink_transform(options)

  fps = options.fetch(:fps, 30).to_f
  speed = options.fetch(:speed, 1.0).to_f
  speed = 1.0 if speed <= 0
  tick_seconds = options.fetch(:tick_seconds, 0.1).to_f
  tick_seconds = 0.1 if tick_seconds <= 0

  # Render “base” images for each tracking frame, then duplicate them according
  # to timeStamp deltas so playback is roughly real-time.
  base_dir = File.join(frames_dir, "_base")
  FileUtils.mkdir_p(base_dir)

  selected.each_with_index do |frame, i|
    on_ice = frame["onIce"] || {}
    entities = on_ice.values.select { |e| e.is_a?(Hash) }
    puck = entities.select { |e| puck_entity?(e) }
    players = entities.reject { |e| puck_entity?(e) }

    out_png = File.join(base_dir, format("base_%05d.png", i))
    cmd = ["magick", background_path]

    # Puck first
    puck.each do |ent|
      x = map_x(ent["x"], tf)
      y = map_y(ent["y"], tf)
      r = 6
      cmd += ["-fill", "#111111", "-stroke", "none", "-draw", "circle #{x},#{y} #{(x + r).round(2)},#{y}"]
    end

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
        "-annotate", "#{dx >= 0 ? "+" : ""}#{dx}#{dy >= 0 ? "+" : ""}#{dy}", num.to_s
      ]
    end

    cmd << out_png
    run_cmd!(cmd, label: "ImageMagick frame render #{i}")
  end

  # Build output frame sequence with repeats based on timeStamp deltas
  time_stamps = selected.map { |f| f.is_a?(Hash) ? f["timeStamp"] : nil }.map { |v| v.is_a?(Numeric) ? v.to_i : nil }
  deltas = []
  time_stamps.each_cons(2) do |a, b|
    deltas << ((a && b) ? (b - a) : nil)
  end
  positive = deltas.compact.select { |d| d > 0 }
  fallback_delta = if positive.empty?
    1
  else
    positive.tally.max_by { |_, c| c }[0]
  end

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

def render_frames_chrome!(selected, options, frames_dir)
  # Optional fallback that uses headless Chrome. This WILL require Chromedriver/Selenium.
  require "base64"
  require "watir"

  w = options[:width].to_i
  h = options[:height].to_i

  html = <<~HTML
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>EDGE Replay PoC</title>
        <style>
          html, body { margin: 0; padding: 0; background: #0b0f14; }
          canvas { display: block; background: #f6fbff; }
        </style>
      </head>
      <body>
        <canvas id="c" width="#{options[:width]}" height="#{options[:height]}"></canvas>
        <script>
          window.FRAMES = #{JSON.generate(selected)};
          const CANVAS_W = #{options[:width]};
          const CANVAS_H = #{options[:height]};
          const RINK_W = #{options[:rink_w]};
          const RINK_H = #{options[:rink_h]};
          const TEAM_COLORS = #{JSON.generate(TEAM_COLORS)};
          const canvas = document.getElementById('c');
          const ctx = canvas.getContext('2d');
          function mapX(x) { return (x / RINK_W) * CANVAS_W; }
          function mapY(y) { return (y / RINK_H) * CANVAS_H; }
          function drawRink() {
            ctx.clearRect(0, 0, CANVAS_W, CANVAS_H);
            ctx.fillStyle = '#f6fbff';
            ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);
          }
          function drawEntity(ent) {
            const x = mapX(ent.x || 0);
            const y = mapY(ent.y || 0);
            const isPuck = (ent.playerId === '' || ent.playerId === null || ent.playerId === undefined) && (ent.teamAbbrev === '' || !ent.teamAbbrev);
            if (isPuck) { ctx.fillStyle = '#111'; ctx.beginPath(); ctx.arc(x,y,6,0,Math.PI*2); ctx.fill(); return; }
            const fill = TEAM_COLORS[ent.teamAbbrev] || '#444';
            ctx.fillStyle = fill; ctx.beginPath(); ctx.arc(x,y,18,0,Math.PI*2); ctx.fill();
            ctx.strokeStyle = '#fff'; ctx.lineWidth = 2; ctx.stroke();
            if (ent.sweaterNumber !== '' && ent.sweaterNumber !== null && ent.sweaterNumber !== undefined) {
              ctx.fillStyle = '#fff'; ctx.font = 'bold 14px ui-sans-serif, system-ui';
              ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
              ctx.fillText(String(ent.sweaterNumber), x, y);
            }
          }
          window.renderFrame = function(i) {
            if (i < 0) i = 0;
            if (i >= window.FRAMES.length) i = window.FRAMES.length - 1;
            drawRink();
            const onIce = window.FRAMES[i].onIce || {};
            Object.values(onIce).forEach(drawEntity);
            return true;
          }
          window.renderFrame(0);
        </script>
      </body>
    </html>
  HTML

  html_path = File.join(frames_dir, "..", "index.html")
  File.write(html_path, html)
  file_url = "file://#{File.expand_path(html_path)}"

  browser = Watir::Browser.new(
    :chrome,
    headless: true,
    options: { args: ["--window-size=#{w},#{h}"] }
  )

  begin
    browser.goto(file_url)
    browser.wait_until(timeout: 10) { browser.canvas(id: "c").exists? }
    selected.length.times do |i|
      browser.execute_script("window.renderFrame(#{i});")
      png_path = File.join(frames_dir, format("frame_%05d.png", i))
      data_url = browser.execute_script("return document.getElementById('c').toDataURL('image/png');")
      b64 = data_url.to_s.split(",", 2)[1]
      raise "Unexpected canvas data URL" if b64.nil? || b64.empty?
      File.binwrite(png_path, Base64.decode64(b64))
    end
  ensure
    browser.close rescue nil
  end
end

options = {
  input: "tmp/edge/ev189.json",
  out: "tmp/edge/edge_replay.mp4",
  renderer: "imagemagick", # imagemagick | chrome
  fps: 30,
  speed: 1.0, # 1.0 = real-time; 0.5 = slower; 2.0 = faster
  tick_seconds: 0.1, # seconds per timeStamp tick (EDGE appears to be 0.1s)
  width: 1280,
  height: 720,
  start: 0,
  frames: nil, # nil => all frames
  rink_w: DEFAULT_RINK_W,
  rink_h: DEFAULT_RINK_H,
  game_id: nil,
  event: nil,
  season: nil,
  game_url: nil,
  user_agent: nil
}

OptionParser.new do |opts|
  opts.banner = "Usage: edge_replay_poc.rb [options]"
  opts.on("--input PATH", "Path to evNNN.json (default: #{options[:input]})") { |v| options[:input] = v }
  opts.on("--game-id ID", "NHL game id (e.g. 2025020501). If --input is missing, we will fetch ev{--event}.json from wsr.nhle.com.") { |v| options[:game_id] = v }
  opts.on("--event N", Integer, "Event id (e.g. 544). Used with --game-id to fetch evN.json from wsr.nhle.com.") { |v| options[:event] = v }
  opts.on("--season SLUG", "Season slug for sprites URL (e.g. 20252026). Defaults to #{'YYYY' + 'YYYY+1'} derived from --game-id.") { |v| options[:season] = v }
  opts.on("--game-url URL", "Referer URL to send when fetching (default: https://www.nhl.com/gamecenter/<game_id>/playbyplay)") { |v| options[:game_url] = v }
  opts.on("--user-agent UA", "User-Agent to send when fetching (default: a Chrome UA)") { |v| options[:user_agent] = v }
  opts.on("--out PATH", "Output mp4 path (default: #{options[:out]})") { |v| options[:out] = v }
  opts.on("--renderer NAME", "Renderer: imagemagick (default) or chrome") { |v| options[:renderer] = v }
  opts.on("--fps N", Integer, "Output video fps (default: #{options[:fps]})") { |v| options[:fps] = v }
  opts.on("--speed X", Float, "Playback speed multiplier (default: #{options[:speed]})") { |v| options[:speed] = v }
  opts.on("--tick-seconds X", Float, "Seconds per timeStamp tick (default: #{options[:tick_seconds]})") { |v| options[:tick_seconds] = v }
  opts.on("--width N", Integer, "Video width (default: #{options[:width]})") { |v| options[:width] = v }
  opts.on("--height N", Integer, "Video height (default: #{options[:height]})") { |v| options[:height] = v }
  opts.on("--start N", Integer, "Start frame index (default: #{options[:start]})") { |v| options[:start] = v }
  opts.on("--frames N", Integer, "How many frames to render (default: all)") { |v| options[:frames] = v }
  opts.on("--rink-w N", Float, "Rink coordinate width (default: #{options[:rink_w]})") { |v| options[:rink_w] = v }
  opts.on("--rink-h N", Float, "Rink coordinate height (default: #{options[:rink_h]})") { |v| options[:rink_h] = v }
end.parse!

input_path = File.expand_path(options[:input])
output_path = File.expand_path(options[:out])

unless File.exist?(input_path)
  if options[:game_id] && options[:event]
    ev = options[:event].to_i
    fetched_path = File.expand_path("tmp/edge/ev#{ev}.json")
    fetched_headers = File.expand_path("tmp/edge/ev#{ev}.headers.txt")
    info = fetch_edge_event_json!(
      game_id: options[:game_id],
      event_id: ev,
      season_slug: options[:season],
      game_url: options[:game_url],
      user_agent: options[:user_agent],
      out_json_path: fetched_path,
      out_headers_path: fetched_headers
    )
    puts "Fetched: #{info[:url]}"
    puts "Saved:   #{info[:json_path]} (#{info[:bytes]} bytes)"
    input_path = info[:json_path]
  else
    warn "Input not found: #{input_path}"
    warn "Provide --game-id and --event to fetch automatically."
    exit 1
  end
end

frames = JSON.parse(File.read(input_path))
unless frames.is_a?(Array) && frames.any?
  warn "Unexpected input shape; expected a non-empty JSON array"
  exit 1
end

start_idx = [options[:start].to_i, 0].max
end_idx = if options[:frames]
  [start_idx + options[:frames].to_i, frames.length].min
else
  frames.length
end
selected = frames[start_idx...end_idx] || []

if selected.empty?
  warn "No frames to render (start=#{start_idx} end=#{end_idx} total=#{frames.length})"
  exit 1
end

FileUtils.mkdir_p(File.dirname(output_path))

Dir.mktmpdir("edge_replay_poc_") do |dir|
  frames_dir = File.join(dir, "frames")
  FileUtils.mkdir_p(frames_dir)

  renderer = options[:renderer].to_s.downcase.strip
  case renderer
  when "imagemagick", "magick", "im"
    render_frames_imagemagick!(selected, options, frames_dir)
  when "chrome"
    render_frames_chrome!(selected, options, frames_dir)
  else
    raise "Unknown renderer: #{options[:renderer]} (use imagemagick or chrome)"
  end

  tmp_out = File.join(dir, "out_#{SecureRandom.hex(4)}.mp4")
  ffmpeg_cmd = [
    "ffmpeg",
    "-y",
    "-hide_banner",
    "-loglevel", "error",
    "-framerate", options[:fps].to_s,
    "-i", File.join(frames_dir, "frame_%05d.png"),
    "-c:v", "libx264",
    "-pix_fmt", "yuv420p",
    "-movflags", "+faststart",
    "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
    tmp_out
  ]
  run_cmd!(ffmpeg_cmd, label: "ffmpeg encode")

  FileUtils.mv(tmp_out, output_path)
  puts "Wrote: #{output_path}"
  puts "Frames: #{selected.length} (source #{File.basename(input_path)}; start=#{start_idx})"
  puts "FPS: #{options[:fps]}  Size: #{options[:width]}x#{options[:height]}  Renderer: #{renderer}"
end



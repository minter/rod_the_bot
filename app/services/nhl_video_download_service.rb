class NhlVideoDownloadService
  require "puppeteer-ruby"
  require "uri"
  require "open3"
  require "securerandom"

  def initialize(nhl_url, output_path = nil)
    @nhl_url = nhl_url
    @output_path = output_path || generate_output_path
  end

  def call
    m3u8_url = get_m3u8_url
    downloaded_file_path = download_video(m3u8_url)
    video = FFMPEG::Movie.new(downloaded_file_path)
    if video.duration > 60.0 || video.size > 50.megabytes
      nhl_url
    else
      downloaded_file_path
    end
  end

  private

  attr_reader :nhl_url, :output_path

  def generate_output_path
    "nhl_video_#{SecureRandom.hex(4)}.mp4"
  end

  def extract_media_url(metrics_url)
    uri = URI.parse(metrics_url)
    query_params = URI.decode_www_form(uri.query).to_h
    media_url = query_params["media_url"]
    URI.decode_www_form_component(media_url)
  end

  def get_m3u8_url
    browser = Puppeteer.launch

    begin
      page = browser.new_page
      metrics_url = nil

      page.on "response" do |response|
        url = response.url
        if url.include?("metrics.brightcove.com") && url.include?("media_url=")
          Rails.logger.info "Found metrics URL: #{url}"
          metrics_url = url
        end
      end

      Rails.logger.info "Navigating to #{nhl_url}"
      page.goto(nhl_url, wait_until: "networkidle0", timeout: 30000)

      Rails.logger.info "Waiting for video player..."
      sleep 5

      handle_play_button(page)
      sleep 10

      unless metrics_url
        Rails.logger.error "Page content: #{page.content}"
        raise "Could not find metrics URL"
      end

      extract_media_url(metrics_url)
    ensure
      browser.close
    end
  rescue => e
    Rails.logger.error "Error getting m3u8 URL: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise e
  end

  def handle_play_button(page)
    play_button_selectors = [
      ".video-player-play-button",
      'button[aria-label="Play"]',
      ".vjs-play-button",
      ".vjs-big-play-button",
      '[class*="play-button"]'
    ]

    play_button = find_play_button(page, play_button_selectors)

    if play_button
      begin
        page.click(play_button)
        Rails.logger.info "Clicked play button"
      rescue => e
        Rails.logger.error "Error clicking play button: #{e.message}"
      end
    else
      Rails.logger.warn "Could not find play button"
    end
  end

  def find_play_button(page, selectors)
    selectors.find do |selector|
      begin
        if page.query_selector(selector)
          Rails.logger.info "Found play button with selector: #{selector}"
          return selector
        end
      rescue => e
        Rails.logger.error "Error checking selector #{selector}: #{e.message}"
      end
      false
    end
  end

  def download_video(m3u8_url)
    Rails.logger.info "Downloading video to: #{output_path}"

    command = [
      "ffmpeg",
      "-y",
      "-i", m3u8_url,
      "-c", "copy",
      output_path
    ]

    # Redirect stderr to stdout and capture all output
    output = `#{command.join(" ")} 2>&1`

    if $?.success?
      Rails.logger.info "Video downloaded successfully to #{output_path}"
      output_path
    else
      Rails.logger.error "ffmpeg output: #{output}"
      raise "ffmpeg failed with status #{$?.exitstatus}"
    end
  end
end

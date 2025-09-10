class NhlVideoDownloadService
  require "watir"
  require "uri"
  require "open3"
  require "securerandom"

  def initialize(nhl_url, output_path = nil)
    @nhl_url = nhl_url
    @output_path = output_path || generate_output_path
  end

  def call
    return mock_video_path if Rails.env.test?

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

  def mock_video_path
    "spec/fixtures/test_video.mp4"
  end

  def generate_output_path
    "nhl_video_#{SecureRandom.hex(4)}.mp4"
  end

  def extract_media_url(metrics_url)
    return nil unless metrics_url

    uri = URI.parse(metrics_url)
    query_params = URI.decode_www_form(uri.query).to_h
    media_url = query_params["media_url"]
    URI.decode_www_form_component(media_url)
  end

  def get_m3u8_url
    retries = 0
    max_retries = 3

    begin
      metrics_url = attempt_browser_launch
      extract_media_url(metrics_url)
    rescue => e
      retries += 1
      Rails.logger.error "Attempt #{retries} failed: #{e.message}"
      if retries < max_retries
        sleep(2**retries) # Exponential backoff
        retry
      else
        raise e
      end
    end
  end

  def attempt_browser_launch
    browser = nil
    metrics_url = nil

    begin
      Rails.logger.info "Launching browser..."
      browser = Watir::Browser.new :chrome,
        headless: true,
        options: {
          args: [
            "--no-sandbox",
            "--disable-gpu",
            "--disable-dev-shm-usage"
          ]
        }

      Rails.logger.info "Navigating to #{nhl_url}"
      browser.goto nhl_url

      # Wait for video player
      Rails.logger.info "Waiting for video player..."
      browser.wait_until(timeout: 10) { browser.video.exists? }

      # Try to find and click play button
      play_button = find_play_button(browser)
      if play_button&.exists? && play_button.visible?
        Rails.logger.info "Clicking play button..."
        play_button.click
      end

      # Wait and extract video URL with timeout
      Rails.logger.info "Waiting for metrics URL..."
      wait_start = Time.now
      while Time.now - wait_start < 15
        metrics_url = browser.execute_script(<<~JS)
          return window.performance
            .getEntries()
            .find(e => e.name.includes('metrics.brightcove.com') && e.name.includes('media_url='))
            ?.name;
        JS
        break if metrics_url

        sleep 0.5
      end

      unless metrics_url
        raise "Could not find metrics URL after timeout"
      end

      metrics_url
    rescue => e
      Rails.logger.error "Browser operation failed: #{e.message}"
      raise e
    ensure
      if browser
        begin
          Rails.logger.info "Closing browser..."
          browser.close
        rescue => e
          Rails.logger.error "Error closing browser: #{e.message}"
          cleanup_zombie_processes
        end
      end
    end
  end

  def find_play_button(browser)
    selectors = [
      {class: "video-player-play-button"},
      {class: "vjs-play-button"},
      {class: "vjs-big-play-button"},
      {text: "Play"}
    ]

    selectors.each do |selector|
      button = browser.button(selector)
      return button if button.exists?
    end

    nil
  end

  def cleanup_zombie_processes
    chrome_pids = `pgrep -f "chrome.*--headless"`.split("\n")
    chrome_pids.each do |pid|
      Process.kill("SIGKILL", pid.to_i)
      Rails.logger.info "Killed zombie Chrome process: #{pid}"
    rescue Errno::ESRCH
      # Process already gone
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

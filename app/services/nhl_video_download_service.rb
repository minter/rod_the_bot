class NhlVideoDownloadService
  require "watir"
  require "uri"
  require "open3"
  require "securerandom"
  require "timeout"

  MAX_DURATION_SECONDS = 10.minutes.to_i
  MAX_VIDEO_BYTES = 290_000_000
  DOWNLOAD_TIMEOUT = 15.minutes
  PROCESS_TERM_GRACE = 5.seconds

  class Error < StandardError; end

  Result = Data.define(:attachment_path, :fallback_url) do
    def attachment?
      attachment_path.present?
    end
  end

  def initialize(nhl_url, output_path = nil)
    @nhl_url = nhl_url
    @output_path = output_path || generate_output_path
  end

  def call
    return Result.new(attachment_path: mock_video_path, fallback_url: nil) if Rails.env.test?

    m3u8_url = get_m3u8_url
    raise Error, "Could not discover an NHL media stream for #{nhl_url}" if m3u8_url.blank?

    downloaded_file_path = download_video(m3u8_url)
    video = FFMPEG::Movie.new(downloaded_file_path)
    if uploadable?(video)
      return Result.new(attachment_path: downloaded_file_path, fallback_url: nil)
    end

    Rails.logger.warn(
      "NhlVideoDownloadService: Falling back to NHL link for #{nhl_url}; " \
      "duration=#{video.duration.round(2)} size=#{video.size}"
    )
    remove_file(downloaded_file_path)
    Result.new(attachment_path: nil, fallback_url: nhl_url)
  rescue
    remove_file(downloaded_file_path)
    raise
  end

  private

  attr_reader :nhl_url, :output_path

  def uploadable?(video)
    video.duration <= MAX_DURATION_SECONDS && video.size <= MAX_VIDEO_BYTES
  end

  def remove_file(path)
    File.unlink(path) if path && File.exist?(path)
  rescue => e
    Rails.logger.warn "NhlVideoDownloadService: Failed to remove #{path}: #{e.message}"
  end

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
        raise
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
      raise
    ensure
      close_browser(browser) if browser
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

  def close_browser(browser)
    Rails.logger.info "Closing browser..."
    browser.close
  rescue => e
    # Selenium's Driver#quit stops its own service process in an ensure block.
    # Avoid process-name sweeps, which can terminate browsers owned by other jobs.
    Rails.logger.error "Error closing browser: #{e.message}"
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

    # Pass arguments directly so remote URLs and local paths are never interpreted
    # by a shell.
    output, status = capture_ffmpeg(command)

    if status.success?
      Rails.logger.info "Video downloaded successfully to #{output_path}"
      output_path
    else
      Rails.logger.error "ffmpeg output: #{output}"
      raise Error, "ffmpeg failed for #{nhl_url} with status #{status.exitstatus}"
    end
  rescue
    remove_file(output_path)
    raise
  end

  def capture_ffmpeg(command)
    Open3.popen2e(*command, pgroup: true) do |_stdin, output, wait_thread|
      log = Timeout.timeout(DOWNLOAD_TIMEOUT) { output.read }
      [log, wait_thread.value]
    rescue Timeout::Error
      terminate_process_group(wait_thread)
      raise Error, "ffmpeg timed out after #{DOWNLOAD_TIMEOUT.inspect} for #{nhl_url}"
    end
  end

  def terminate_process_group(wait_thread)
    Process.kill("TERM", -wait_thread.pid)
    return if wait_thread.join(PROCESS_TERM_GRACE)

    Process.kill("KILL", -wait_thread.pid)
    wait_thread.join
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end
end

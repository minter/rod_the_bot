require "test_helper"

class NhlVideoDownloadServiceTest < ActiveSupport::TestCase
  test "download_video passes the media URL to ffmpeg without a shell" do
    media_url = "https://media.example/video.m3u8?token=a&next=$(touch hacked)"
    output_path = Rails.root.join("tmp", "downloaded video.mp4").to_s
    status = mock("status")
    status.stubs(:success?).returns(true)
    Open3.expects(:capture2e).with(
      "ffmpeg", "-y", "-i", media_url, "-c", "copy", output_path
    ).returns(["ffmpeg output", status])

    service = NhlVideoDownloadService.new("https://www.nhl.com/video/example", output_path)

    assert_equal output_path, service.send(:download_video, media_url)
  end

  test "accepts videos within the ten-minute and Bluesky size limits" do
    video = mock("video")
    video.stubs(:duration).returns(597.6)
    video.stubs(:size).returns(270_495_887)
    service = NhlVideoDownloadService.new("https://www.nhl.com/video/example")

    assert service.send(:uploadable?, video)
  end

  test "rejects videos over ten minutes or the buffered size limit" do
    service = NhlVideoDownloadService.new("https://www.nhl.com/video/example")

    long_video = mock("long video")
    long_video.stubs(:duration).returns(600.1)
    long_video.stubs(:size).returns(100_000_000)
    large_video = mock("large video")
    large_video.stubs(:duration).returns(500.0)
    large_video.stubs(:size).returns(290_000_001)

    refute service.send(:uploadable?, long_video)
    refute service.send(:uploadable?, large_video)
  end

  test "removes an oversized download before falling back to the NHL page" do
    output_path = Rails.root.join("tmp", "oversized-recap.mp4").to_s
    FileUtils.touch(output_path)
    service = NhlVideoDownloadService.new("https://www.nhl.com/video/example", output_path)
    service.stubs(:get_m3u8_url).returns("https://media.example/master.m3u8")
    service.stubs(:download_video).returns(output_path)
    video = mock("video")
    video.stubs(:duration).returns(601.0)
    video.stubs(:size).returns(100_000_000)
    FFMPEG::Movie.expects(:new).with(output_path).returns(video)
    Rails.env.stubs(:test?).returns(false)

    assert_equal "https://www.nhl.com/video/example", service.call
    refute_path_exists output_path
  ensure
    File.unlink(output_path) if output_path && File.exist?(output_path)
  end
end

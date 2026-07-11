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
end

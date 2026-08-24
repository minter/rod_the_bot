require "test_helper"

class RodTheBot::GameVideoWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::GameVideoWorker.new
    @game_id = 2025030134
  end

  test "downloads and attaches the three-minute recap" do
    stub_video("threeMinRecap", 6393888986112, "/rails/tmp/recap.mp4")

    @worker.perform(@game_id, "threeMinRecap")

    job = RodTheBot::Post.jobs.last
    assert_equal "🎥 Game recap: Carolina at Ottawa on April 25, 2026.", job["args"][0]
    assert_equal({"video_file_path" => "/rails/tmp/recap.mp4"}, job["args"][1])
  end

  test "downloads and attaches the condensed game" do
    stub_video("condensedGame", 6393887997112, "/rails/tmp/condensed.mp4")

    @worker.perform(@game_id, "condensedGame")

    job = RodTheBot::Post.jobs.last
    assert_equal "🎥 Condensed game: Carolina at Ottawa on April 25, 2026.", job["args"][0]
    assert_equal({"video_file_path" => "/rails/tmp/condensed.mp4"}, job["args"][1])
  end

  test "falls back to the NHL page when the media exceeds upload limits" do
    url = "https://www.nhl.com/video/car-at-ott-condensed-game-6393887997112"
    stub_video("condensedGame", 6393887997112, url)

    @worker.perform(@game_id, "condensedGame")

    job = RodTheBot::Post.jobs.last
    assert_equal({"embed_url" => url}, job["args"][1])
  end

  test "reschedules unavailable video with a bound" do
    Nhl::GameVideo.expects(:find).with(@game_id, "condensedGame").returns(nil)

    @worker.perform(@game_id, "condensedGame", 1)

    job = RodTheBot::GameVideoWorker.jobs.last
    assert_equal [@game_id, "condensedGame", 2], job["args"]
    assert_in_delta 10.minutes, job["at"] - Time.now.to_f, 1
  end

  test "discards unknown video types" do
    Nhl::GameVideo.expects(:find).raises(Nhl::GameVideo::UnknownType, "unknown video type")

    assert_no_difference -> { RodTheBot::Post.jobs.size } do
      @worker.perform(@game_id, "fullGame")
    end
  end

  test "discards permanently malformed video metadata" do
    Nhl::GameVideo.expects(:find).raises(Nhl::GameVideo::MalformedVideo, "invalid game date")

    assert_no_difference -> { RodTheBot::Post.jobs.size } do
      @worker.perform(@game_id, "condensedGame")
    end
  end

  test "removes downloaded media when enqueueing the post fails" do
    path = Rails.root.join("tmp", "unqueued-recap.mp4").to_s
    FileUtils.touch(path)
    stub_video("threeMinRecap", 6393888986112, path)
    RodTheBot::Post.expects(:perform_async).raises(StandardError, "Redis unavailable")

    assert_raises StandardError do
      @worker.perform(@game_id, "threeMinRecap")
    end
    refute_path_exists path
  ensure
    File.unlink(path) if path && File.exist?(path)
  end

  private

  def stub_video(type, id, result)
    slug = (type == "threeMinRecap") ? "recap" : "condensed-game"
    video = Nhl::GameVideo::Video.new(
      id: id,
      type: type,
      source_url: "https://www.nhl.com/video/car-at-ott-#{slug}-#{id}",
      label: (type == "threeMinRecap") ? "Game recap" : "Condensed game",
      away_name: "Carolina",
      home_name: "Ottawa",
      date: Date.new(2026, 4, 25)
    )
    Nhl::GameVideo.expects(:find).with(@game_id, type).returns(video)
    service = mock("video download")
    media = if result.start_with?("http")
      NhlVideoDownloadService::Result.new(attachment_path: nil, fallback_url: result)
    else
      NhlVideoDownloadService::Result.new(attachment_path: result, fallback_url: nil)
    end
    service.expects(:call).returns(media)
    expected_url = "https://www.nhl.com/video/car-at-ott-#{slug}-#{id}"
    path = %r{/tmp/#{type.underscore}_#{@game_id}_#{id}_[a-f0-9]{8}\.mp4\z}
    NhlVideoDownloadService.expects(:new).with(expected_url, regexp_matches(path)).returns(service)
  end
end

require "test_helper"

class RodTheBot::GameVideoWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::GameVideoWorker.new
    @game_id = 2025030134
    @boxscore = {
      "gameDate" => "2026-04-25",
      "awayTeam" => {"abbrev" => "CAR", "placeName" => {"default" => "Carolina"}},
      "homeTeam" => {"abbrev" => "OTT", "placeName" => {"default" => "Ottawa"}}
    }
  end

  test "downloads and attaches the three-minute recap" do
    stub_video("threeMinRecap", 6393888986112, "/rails/tmp/recap.mp4")

    @worker.perform(@game_id, "threeMinRecap")

    job = RodTheBot::Post.jobs.last
    assert_equal "🎥 Game recap: Carolina at Ottawa on April 25, 2026.", job["args"][0]
    assert_nil job["args"][3]
    assert_equal "/rails/tmp/recap.mp4", job["args"][5]
  end

  test "downloads and attaches the condensed game" do
    stub_video("condensedGame", 6393887997112, "/rails/tmp/condensed.mp4")

    @worker.perform(@game_id, "condensedGame")

    job = RodTheBot::Post.jobs.last
    assert_equal "🎥 Condensed game: Carolina at Ottawa on April 25, 2026.", job["args"][0]
    assert_equal "/rails/tmp/condensed.mp4", job["args"][5]
  end

  test "falls back to the NHL page when the media exceeds upload limits" do
    url = "https://www.nhl.com/video/car-at-ott-condensed-game-6393887997112"
    stub_video("condensedGame", 6393887997112, url)

    @worker.perform(@game_id, "condensedGame")

    job = RodTheBot::Post.jobs.last
    assert_equal url, job["args"][3]
    assert_nil job["args"][5]
  end

  test "reschedules unavailable video with a bound" do
    Nhl::GameClient.stubs(:boxscore).returns(@boxscore)
    Nhl::GameClient.stubs(:right_rail).returns("gameVideo" => {})

    @worker.perform(@game_id, "condensedGame", 1)

    job = RodTheBot::GameVideoWorker.jobs.last
    assert_equal [@game_id, "condensedGame", 2], job["args"]
    assert_in_delta 10.minutes, job["at"] - Time.now.to_f, 1
  end

  test "discards unknown video types" do
    Nhl::GameClient.expects(:boxscore).never

    assert_no_difference -> { RodTheBot::Post.jobs.size } do
      @worker.perform(@game_id, "fullGame")
    end
  end

  private

  def stub_video(type, id, result)
    Nhl::GameClient.stubs(:boxscore).returns(@boxscore)
    Nhl::GameClient.stubs(:right_rail).returns("gameVideo" => {type => id})
    service = mock("video download")
    service.expects(:call).returns(result)
    slug = (type == "threeMinRecap") ? "recap" : "condensed-game"
    expected_url = "https://www.nhl.com/video/car-at-ott-#{slug}-#{id}"
    path = %r{/tmp/#{type.underscore}_#{@game_id}_#{id}_[a-f0-9]{8}\.mp4\z}
    NhlVideoDownloadService.expects(:new).with(expected_url, regexp_matches(path)).returns(service)
  end
end

require "test_helper"

class RodTheBot::EndOfPeriodShotChartWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @game_id = 2024020477
  end

  def test_posts_video_when_service_returns_path
    fake_path = Pathname.new("test/fixtures/files/test_shot_chart.mp4")
    feed = {"homeTeam" => {"abbrev" => "EDM", "sog" => 21}, "awayTeam" => {"abbrev" => "VGK", "sog" => 17}}
    Nhl::GameClient.stubs(:play_by_play).with(@game_id).returns(feed)
    RodTheBot::ShotChartAnimator.any_instance.stubs(:call).returns(fake_path)

    RodTheBot::EndOfPeriodShotChartWorker.new.perform(@game_id, 1)

    assert_equal 1, RodTheBot::Post.jobs.size
    args = RodTheBot::Post.jobs.first["args"]
    expected_text = <<~POST
      🏒 Shot chart through the 1st period.

      VGK: 17 SOG
      EDM: 21 SOG
    POST
    assert_equal expected_text, args[0]
    # Post.perform args: post, key, parent_key, embed_url, embed_images, video_file_path, root_key
    assert_equal fake_path.to_s, args[5]
  end

  def test_no_op_when_service_returns_nil
    Nhl::GameClient.stubs(:play_by_play).returns({"homeTeam" => {}, "awayTeam" => {}})
    RodTheBot::ShotChartAnimator.any_instance.stubs(:call).returns(nil)

    RodTheBot::EndOfPeriodShotChartWorker.new.perform(@game_id, 1)

    assert_equal 0, RodTheBot::Post.jobs.size
  end

  def test_raises_exceptions_for_sidekiq_retry
    Nhl::GameClient.stubs(:play_by_play).raises(StandardError, "boom")

    assert_raises(StandardError) do
      RodTheBot::EndOfPeriodShotChartWorker.new.perform(@game_id, 1)
    end
    assert_equal 0, RodTheBot::Post.jobs.size
  end
end

require "test_helper"

class RodTheBot::ShotChartAnimatorTest < ActiveSupport::TestCase
  def test_short_circuits_in_test_env
    path = RodTheBot::ShotChartAnimator.new(game_id: 2024020477, through_period: 1).call
    assert_kind_of Pathname, path
    assert_equal "test_shot_chart.mp4", path.basename.to_s
  end

  def test_returns_nil_when_no_plottable_shots
    Rails.env.stubs(:test?).returns(false)
    NhlApi.stubs(:fetch_pbp_feed).returns({"homeTeam" => {"id" => 1, "abbrev" => "HME"},
                                            "awayTeam" => {"id" => 2, "abbrev" => "AWY"},
                                            "plays" => []})
    result = RodTheBot::ShotChartAnimator.new(game_id: 1, through_period: 1).call
    assert_nil result
  end

  def test_idempotent_returns_existing_mp4
    Rails.env.stubs(:test?).returns(false)
    Dir.mktmpdir do |tmp|
      RodTheBot::ShotChartAnimator.any_instance.stubs(:output_dir).returns(Pathname.new(tmp))
      target = Pathname.new(tmp).join("p1.mp4")
      target.write("placeholder")

      NhlApi.stubs(:fetch_pbp_feed).returns({"homeTeam" => {"id" => 1, "abbrev" => "HME"},
                                              "awayTeam" => {"id" => 2, "abbrev" => "AWY"},
                                              "plays" => []})

      result = RodTheBot::ShotChartAnimator.new(game_id: 1, through_period: 1).call
      assert_equal target, result
    end
  end
end

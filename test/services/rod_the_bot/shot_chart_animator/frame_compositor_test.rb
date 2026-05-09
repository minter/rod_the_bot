require "test_helper"

class RodTheBot::ShotChartAnimator::FrameCompositorTest < ActiveSupport::TestCase
  def setup
    @rink = Tempfile.new(["rink", ".png"])
    RodTheBot::ShotChartAnimator::RinkRenderer.call(@rink.path)
  end

  def teardown
    @rink&.close!
  end

  def test_compose_writes_png_with_canvas_dimensions
    Dir.mktmpdir do |tmp|
      out = File.join(tmp, "frame.png")
      shots = [
        {x: 50, y: 0, type: "shot-on-goal", team_side: :home, period: 1, time_in_period: "10:00"},
        {x: -50, y: 5, type: "goal", team_side: :away, period: 1, time_in_period: "11:30",
         goal_number: 1}
      ]
      RodTheBot::ShotChartAnimator::FrameCompositor.compose(
        rink_path: @rink.path,
        out_path: out,
        prior_shots: [shots.first],
        new_shots: [shots.last],
        new_shot_scale: 1.0,
        active_caption: nil,
        away_abbrev: "AWY",
        home_abbrev: "HME",
        away_color: "#000000",
        home_color: "#FFFFFF",
        period_label: "End of 1st",
        away_sog: 1, home_sog: 1
      )

      assert File.exist?(out)
      img = MiniMagick::Image.open(out)
      assert_equal 1200, img.width
      assert_equal 510, img.height
    end
  end

  def test_compose_handles_zero_shots
    Dir.mktmpdir do |tmp|
      out = File.join(tmp, "frame.png")
      RodTheBot::ShotChartAnimator::FrameCompositor.compose(
        rink_path: @rink.path,
        out_path: out,
        prior_shots: [],
        new_shots: [],
        new_shot_scale: 1.0,
        active_caption: nil,
        away_abbrev: "AWY",
        home_abbrev: "HME",
        away_color: "#000000",
        home_color: "#FFFFFF",
        period_label: "End of 1st",
        away_sog: 0, home_sog: 0
      )
      assert File.exist?(out)
    end
  end
end

require "test_helper"

class RodTheBot::ShotChartAnimator::RinkRendererTest < ActiveSupport::TestCase
  def test_call_returns_path_to_canvas_sized_png
    Dir.mktmpdir do |tmp|
      out = File.join(tmp, "rink.png")
      RodTheBot::ShotChartAnimator::RinkRenderer.call(out)
      assert File.exist?(out), "rink png should be written"
      img = MiniMagick::Image.open(out)
      assert_equal 1200, img.width
      assert_equal 510, img.height
    end
  end

  def test_call_with_logos_still_produces_canvas_sized_png
    Dir.mktmpdir do |tmp|
      # Create a fake logo PNG (any valid PNG content)
      fake_logo = File.join(tmp, "logo.png")
      MiniMagick::Tool.new(RodTheBot::ShotChartAnimator::IM_BINARY) do |c|
        c.size("64x64")
        c.canvas("#FF0000")
        c << fake_logo
      end

      out = File.join(tmp, "rink.png")
      RodTheBot::ShotChartAnimator::RinkRenderer.call(out, home_logo_path: fake_logo, away_logo_path: fake_logo)
      assert File.exist?(out)
      img = MiniMagick::Image.open(out)
      assert_equal 1200, img.width
      assert_equal 510, img.height
    end
  end
end

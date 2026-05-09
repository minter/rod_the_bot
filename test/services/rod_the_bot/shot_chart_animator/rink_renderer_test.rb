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
end

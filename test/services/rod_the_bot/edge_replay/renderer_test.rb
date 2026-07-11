require "test_helper"

class RodTheBot::EdgeReplay::RendererTest < ActiveSupport::TestCase
  test "default geometry fits the source rink inside the output canvas" do
    renderer = RodTheBot::EdgeReplay::Renderer.new
    options = renderer.default_options
    transform = renderer.rink_transform(options)

    assert_operator transform[:x0], :>=, 0
    assert_operator transform[:y0], :>=, 0
    assert_operator transform[:x1], :<=, options[:width]
    assert_operator transform[:y1], :<=, options[:height]
  end
end

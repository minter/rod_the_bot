require "test_helper"

class RodTheBot::ShotChartAnimator::CoordNormalizerTest < ActiveSupport::TestCase
  CN = RodTheBot::ShotChartAnimator::CoordNormalizer

  def test_normalize_does_not_flip_when_home_attacks_right
    nx, ny = CN.normalize(x: 50, y: 10, home_defending_side: "left")
    assert_equal 50, nx
    assert_equal 10, ny
  end

  def test_normalize_flips_when_home_defends_right
    nx, ny = CN.normalize(x: 50, y: 10, home_defending_side: "right")
    assert_equal(-50, nx)
    assert_equal(-10, ny)
  end

  def test_to_canvas_maps_center_ice_to_canvas_center
    cx, cy = CN.to_canvas(0, 0)
    assert_in_delta 600.0, cx, 0.001
    assert_in_delta 255.0, cy, 0.001
  end

  def test_to_canvas_maps_offensive_corner
    cx, cy = CN.to_canvas(100, 42.5)
    assert_in_delta 1200.0, cx, 0.001
    assert_in_delta 510.0, cy, 0.001
  end

  def test_to_canvas_maps_defensive_corner
    cx, cy = CN.to_canvas(-100, -42.5)
    assert_in_delta 0.0, cx, 0.001
    assert_in_delta 0.0, cy, 0.001
  end
end

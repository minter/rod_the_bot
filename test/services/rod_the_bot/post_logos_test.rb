require "test_helper"

class RodTheBot::PostLogosTest < ActiveSupport::TestCase
  test "renders transparent logos on white while preserving their artwork" do
    svg = '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect x="5" y="5" width="10" height="10" fill="#00205b"/></svg>'
    HTTParty.stubs(:get).returns(stub(success?: true, body: svg))
    path = nil

    RodTheBot::PostLogos.with_images(["https://example.com/team.svg"]) do |images|
      path = images.first.path
      image = MiniMagick::Image.open(path)
      assert_equal [255, 255, 255], image.get_pixels[0][0].first(3)
      assert_equal [0, 32, 91], image.get_pixels[300][300].first(3)
    end

    assert_not File.exist?(path)
  end

  test "raises on unsuccessful downloads" do
    HTTParty.stubs(:get).returns(stub(success?: false, code: 503))
    assert_raises(RodTheBot::PostLogos::Error) do
      RodTheBot::PostLogos.with_images(["https://example.com/team.svg"]) { flunk "should not yield" }
    end
  end
end

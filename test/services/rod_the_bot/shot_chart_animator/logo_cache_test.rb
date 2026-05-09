require "test_helper"

class RodTheBot::ShotChartAnimator::LogoCacheTest < ActiveSupport::TestCase
  LC = RodTheBot::ShotChartAnimator::LogoCache

  def setup
    @tmp = Pathname.new(Dir.mktmpdir)
    LC.stubs(:logo_dir).returns(@tmp)
  end

  def teardown
    FileUtils.rm_rf(@tmp)
  end

  def test_returns_nil_when_abbrev_blank
    assert_nil LC.fetch(team_abbrev: "", logo_url: "https://example.com/logo.svg")
    assert_nil LC.fetch(team_abbrev: nil, logo_url: "https://example.com/logo.svg")
  end

  def test_returns_nil_when_url_blank
    assert_nil LC.fetch(team_abbrev: "EDM", logo_url: "")
    assert_nil LC.fetch(team_abbrev: "EDM", logo_url: nil)
  end

  def test_returns_existing_cached_png_without_fetching
    cached = @tmp.join("EDM.png")
    cached.write("FAKE_PNG_DATA")

    HTTParty.expects(:get).never

    result = LC.fetch(team_abbrev: "EDM", logo_url: "https://example.com/logo.svg")
    assert_equal cached, result
  end

  def test_returns_nil_when_http_fails
    failed_response = mock
    failed_response.stubs(:success?).returns(false)
    HTTParty.stubs(:get).returns(failed_response)

    result = LC.fetch(team_abbrev: "ZZZ", logo_url: "https://example.com/missing.svg")
    assert_nil result
  end
end

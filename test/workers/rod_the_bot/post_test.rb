require "test_helper"

class RodTheBot::PostTest < ActiveSupport::TestCase
  def setup
    @post = RodTheBot::Post.new
    @bsky = mock("bsky")

    # Set @bsky directly
    @post.bsky = @bsky

    # Stub REDIS.get and REDIS.set to avoid actual Redis calls
    REDIS.stubs(:get).returns(nil)
    REDIS.stubs(:set).returns(nil)
  end

  def test_perform
    ENV["BLUESKY_ENABLED"] = "true"
    ENV["TEAM_HASHTAGS"] = "#team"

    @bsky.expects(:create_post).with(
      "test post\n#team",
      embed_url: nil,
      embed_images: [],
      embed_video: nil
    ).returns({"uri" => "test_uri"})

    assert_nothing_raised do
      @post.perform("test post")
    end
  end

  def test_perform_bluesky_disabled
    ENV["BLUESKY_ENABLED"] = "false"
    ENV["TEAM_HASHTAGS"] = "#team"

    @bsky.expects(:create_post).never

    assert_nothing_raised do
      @post.perform("test post")
    end
  end

  def test_append_team_hashtags
    ENV["TEAM_HASHTAGS"] = "#team"
    result = @post.send(:append_team_hashtags, "test post")
    assert_equal "test post\n#team", result
  end

  def test_log_post
    ENV["DEBUG_POSTS"] = "true"
    Rails.logger.expects(:info).with("DEBUG: test post")
    @post.send(:log_post, "test post")
  end
end

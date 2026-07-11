require "test_helper"

class RodTheBot::PostTest < ActiveSupport::TestCase
  def setup
    @post = RodTheBot::Post.new
    @bsky = mock("bsky")
    @original_env = ENV.to_h

    # Set @bsky directly
    @post.bsky = @bsky

    # Stub REDIS.get and REDIS.set to avoid actual Redis calls
    REDIS.stubs(:get).returns(nil)
    REDIS.stubs(:set).returns(nil)
  end

  def teardown
    ENV.replace(@original_env)
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

  def test_perform_reraises_posting_failures_and_preserves_video_for_retry
    ENV["BLUESKY_ENABLED"] = "true"
    video = Tempfile.new(["post-retry", ".mp4"])
    video.close
    @bsky.expects(:create_post).raises(StandardError, "temporary outage")

    error = assert_raises(StandardError) do
      @post.perform("test post", nil, nil, nil, [], video.path)
    end

    assert_equal "temporary outage", error.message
    assert_path_exists video.path
  ensure
    video&.unlink
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

  def test_perform_logs_debug_post_when_bluesky_disabled_without_session
    post = RodTheBot::Post.new
    ENV["BLUESKY_ENABLED"] = "false"
    ENV["DEBUG_POSTS"] = "true"
    ENV["TEAM_HASHTAGS"] = "#team"

    Rails.logger.expects(:info).with("DEBUG: test post\n#team")

    assert_nothing_raised do
      post.perform("test post")
    end
  end

  def test_create_session_uses_bskyrb_session
    post = RodTheBot::Post.new
    credentials = mock("credentials")
    session = mock("session")
    bsky = mock("bsky")

    ENV["BLUESKY_ENABLED"] = "true"
    ENV["BLUESKY_USERNAME"] = "test.bsky.social"
    ENV["BLUESKY_APP_PASSWORD"] = "app-password"
    ENV["BLUESKY_URL"] = "https://pds.example"

    Rails.env.stubs(:test?).returns(false)
    ATProto::Credentials.expects(:new).with("test.bsky.social", "app-password", "https://pds.example").returns(credentials)
    ATProto::Session.expects(:new).with(credentials).returns(session)
    Bskyrb::Client.expects(:new).with(session).returns(bsky)

    assert_equal bsky, post.send(:create_session)
  end

  def test_validate_bluesky_credentials_reports_missing_env_vars
    post = RodTheBot::Post.new
    ENV.delete("BLUESKY_USERNAME")
    ENV.delete("BLUESKY_APP_PASSWORD")

    error = assert_raises(ArgumentError) do
      post.send(:validate_bluesky_credentials!)
    end

    assert_equal "Missing required Bluesky configuration: BLUESKY_USERNAME, BLUESKY_APP_PASSWORD", error.message
  end
end

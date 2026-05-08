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

  def test_open_atproto_session_handles_create_session_without_did_doc
    post = RodTheBot::Post.new
    credentials = ATProto::Credentials.new("test.bsky.social", "app-password", "https://bsky.social")
    session = ATProto::Session.new(credentials, false)

    create_session_response = mock("create_session_response")
    create_session_response.stubs(:code).returns(200)
    create_session_response.stubs(:success?).returns(true)
    create_session_response.stubs(:[]).with("accessJwt").returns("ACCESS_JWT")
    create_session_response.stubs(:[]).with("refreshJwt").returns("REFRESH_JWT")
    create_session_response.stubs(:[]).with("did").returns("did:plc:test")
    create_session_response.stubs(:[]).with("didDoc").returns(nil)

    did_doc = {
      "service" => [
        {"serviceEndpoint" => "https://morel.us-east.host.bsky.network"}
      ]
    }
    resolve_did_response = mock("resolve_did_response")
    resolve_did_response.stubs(:success?).returns(true)
    resolve_did_response.stubs(:[]).with("didDoc").returns(did_doc)

    HTTParty.expects(:post).returns(create_session_response)
    HTTParty.expects(:get).returns(resolve_did_response)

    post.send(:open_atproto_session, session)

    assert_equal "ACCESS_JWT", session.access_token
    assert_equal "REFRESH_JWT", session.refresh_token
    assert_equal "did:plc:test", session.did
    assert_equal "did:web:morel.us-east.host.bsky.network", session.service_endpoint
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

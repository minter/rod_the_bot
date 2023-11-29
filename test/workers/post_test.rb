require "test_helper"
require "minitest/mock"

class PostTest < ActiveSupport::TestCase
  def setup
    @post = RodTheBot::Post.new
    @session = Minitest::Mock.new
    @bsky = Minitest::Mock.new
    @credentials = Minitest::Mock.new
  end

  def test_perform
    ENV["BLUESKY_ENABLED"] = "true"
    ENV["TEAM_HASHTAGS"] = "#team"
    Bskyrb::Credentials.stub :new, @credentials do
      Bskyrb::Session.stub :new, @session do
        Bskyrb::RecordManager.stub :new, @bsky do
          @bsky.expect :create_post, nil, ["test post\n#team"]
          @post.perform("test post")
          @bsky.verify
        end
      end
    end
  end

  def test_append_team_hashtags
    ENV["TEAM_HASHTAGS"] = "#team"
    result = @post.send(:append_team_hashtags, "test post")
    assert_equal "test post\n#team", result
  end

  def test_log_post
    ENV["DEBUG_POSTS"] = "true"
    Rails.logger.stub :info, nil do
      @post.send(:log_post, "test post")
    end
  end
end

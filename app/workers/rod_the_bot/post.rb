module RodTheBot
  class Post
    include Sidekiq::Worker

    def perform(post)
      session = create_session
      post = append_team_hashtags(post)
      create_post(session, post)
      log_post(post)
    end

    private

    def create_session
      credentials = Bskyrb::Credentials.new(ENV["BLUESKY_USERNAME"], ENV["BLUESKY_APP_PASSWORD"])
      Bskyrb::Session.new(credentials, ENV["BLUESKY_URL"])
    end

    def append_team_hashtags(post)
      post += "\n#{ENV["TEAM_HASHTAGS"]}" if ENV["TEAM_HASHTAGS"]
      post
    end

    def create_post(session, post)
      bsky = Bskyrb::RecordManager.new(session)
      bsky.create_post(post) if ENV["BLUESKY_ENABLED"] == "true"
    end

    def log_post(post)
      Rails.logger.info "DEBUG: #{post}" if ENV["DEBUG_POSTS"] == "true"
    end
  end
end

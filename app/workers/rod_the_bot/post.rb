module RodTheBot
  class Post
    include Sidekiq::Worker

    def perform(post, key = nil)
      create_session
      return if @bsky.nil?
      post = append_team_hashtags(post)
      reply_uri = REDIS.get(key) if key
      if reply_uri
        create_reply(reply_uri, post)
      else
        new_post = create_post(post)
        post_uri = new_post["uri"] if new_post
        REDIS.set(key, post_uri, ex: 172800) if key
      end
      log_post(post)
    end

    private

    def create_session
      unless Rails.env.test?
        credentials = ATProto::Credentials.new(ENV["BLUESKY_USERNAME"], ENV["BLUESKY_APP_PASSWORD"])
        session = ATProto::Session.new(credentials)
        @bsky = Bskyrb::Client.new(session)
      end
    end

    def append_team_hashtags(post)
      post += "\n#{ENV["TEAM_HASHTAGS"]}" if ENV["TEAM_HASHTAGS"]
      post
    end

    def create_post(post)
      @bsky.create_post(post) if ENV["BLUESKY_ENABLED"] == "true"
    end

    def create_reply(reply_uri, post)
      @bsky.create_reply(reply_uri, post) if ENV["BLUESKY_ENABLED"] == "true"
    end

    def log_post(post)
      Rails.logger.info "DEBUG: #{post}" if ENV["DEBUG_POSTS"] == "true"
    end
  end
end

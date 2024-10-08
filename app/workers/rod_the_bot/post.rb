module RodTheBot
  class Post
    include Sidekiq::Worker

    attr_writer :bsky

    def perform(post, key = nil, embed_url = nil)
      create_session
      return if @bsky.nil?
      post = append_team_hashtags(post)
      reply_uri = REDIS.get(key) if key

      if ENV["BLUESKY_ENABLED"] == "true"
        new_post = if reply_uri
          create_reply(reply_uri, post, embed_url: embed_url)
        else
          Rails.logger.info "No existing post found for key: #{key}. Creating new post."
          create_post(post, embed_url: embed_url)
        end
      end

      if ENV["BLUESKY_ENABLED"] == "true" && new_post && new_post["uri"]
        post_uri = new_post["uri"]
        REDIS.set(key, post_uri, ex: 172800) if key
      end

      if ENV["DEBUG_POSTS"] == "true"
        log_post(post)
      end
    end

    private

    def create_session
      return @bsky if @bsky # Return existing session if available
      return if Rails.env.test? # Skip actual creation in test environment
      credentials = ATProto::Credentials.new(ENV["BLUESKY_USERNAME"], ENV["BLUESKY_APP_PASSWORD"])
      session = ATProto::Session.new(credentials)
      @bsky = Bskyrb::Client.new(session)
    end

    def append_team_hashtags(post)
      post += "\n#{ENV["TEAM_HASHTAGS"]}" if ENV["TEAM_HASHTAGS"]
      post
    end

    def create_post(post, embed_url: nil)
      return unless ENV["BLUESKY_ENABLED"] == "true"
      @bsky.create_post(post, embed_url: embed_url)
    end

    def create_reply(reply_uri, post, embed_url: nil)
      return unless ENV["BLUESKY_ENABLED"] == "true"
      Rails.logger.info "Creating reply to #{reply_uri} with post #{post} and embed_url #{embed_url}"
      @bsky.create_reply(reply_uri, post, embed_url: embed_url)
    end

    def log_post(post)
      Rails.logger.info "DEBUG: #{post}" if ENV["DEBUG_POSTS"] == "true"
    end
  end
end

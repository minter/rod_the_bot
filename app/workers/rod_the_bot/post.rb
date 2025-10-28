module RodTheBot
  class Post
    include Sidekiq::Worker

    attr_writer :bsky

    def perform(post, key = nil, parent_key = nil, embed_url = nil, embed_images = [], video_file_path = nil)
      create_session
      return if @bsky.nil?

      post = append_team_hashtags(post)

      parent_uri = REDIS.get(parent_key) if parent_key
      reply_uri = REDIS.get(key) if key && !parent_key

      if ENV["BLUESKY_ENABLED"] == "true"
        new_post = if parent_uri
          create_reply(parent_uri, post, embed_url: embed_url, embed_images: embed_images, embed_video: video_file_path)
        elsif reply_uri
          create_reply(reply_uri, post, embed_url: embed_url, embed_images: embed_images, embed_video: video_file_path)
        else
          Rails.logger.info "No parent post found. Creating new post."
          create_post(post, embed_url: embed_url, embed_images: embed_images, embed_video: video_file_path)
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

    def create_post(post, embed_url: nil, embed_images: [], embed_video: nil)
      return unless ENV["BLUESKY_ENABLED"] == "true"

      # Filter out nil values from embed_images - Bsky client expects String (URL) or File objects only
      embed_images = Array(embed_images).compact

      post = @bsky.create_post(post, embed_url: embed_url, embed_images: embed_images, embed_video: embed_video)
      File.unlink(embed_video) if embed_video && File.exist?(embed_video)
      post
    end

    def create_reply(reply_uri, post, embed_url: nil, embed_images: [], embed_video: nil)
      return unless ENV["BLUESKY_ENABLED"] == "true"

      # Filter out nil values from embed_images - Bsky client expects String (URL) or File objects only
      embed_images = Array(embed_images).compact

      Rails.logger.info "Creating reply to #{reply_uri} with post #{post} and embed_url #{embed_url}"
      post = @bsky.create_reply(reply_uri, post, embed_url: embed_url, embed_images: embed_images, embed_video: embed_video)
      File.unlink(embed_video) if embed_video && File.exist?(embed_video)
      post
    end

    def log_post(post)
      Rails.logger.info "DEBUG: #{post}" if ENV["DEBUG_POSTS"] == "true"
    end
  end
end

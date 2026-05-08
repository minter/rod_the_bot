module RodTheBot
  class Post
    include Sidekiq::Worker

    attr_writer :bsky

    def perform(post, key = nil, parent_key = nil, embed_url = nil, embed_images = [], video_file_path = nil, root_key = nil)
      post = append_team_hashtags(post)
      new_post = nil

      if bluesky_enabled?
        create_session
        return if @bsky.nil?

        parent_uri = REDIS.get(parent_key) if parent_key
        reply_uri = REDIS.get(key) if key && !parent_key
        new_post = if parent_uri
          create_reply(parent_uri, post, embed_url: embed_url, embed_images: embed_images, embed_video: video_file_path)
        elsif reply_uri
          create_reply(reply_uri, post, embed_url: embed_url, embed_images: embed_images, embed_video: video_file_path)
        else
          Rails.logger.info "No parent post found. Creating new post."
          create_post(post, embed_url: embed_url, embed_images: embed_images, embed_video: video_file_path)
        end
      end

      if bluesky_enabled? && new_post && new_post["uri"]
        post_uri = new_post["uri"]
        REDIS.set(key, post_uri, ex: 172800) if key

        # Update last_reply_key tracker atomically after successful post
        # This ensures threading stays correct even with concurrent workers
        if root_key && parent_key && key
          update_last_reply_tracker(root_key, key)
        end
      end

      if ENV["DEBUG_POSTS"] == "true"
        log_post(post)
      end
    rescue => e
      Rails.logger.error "Post: Failed to post to Bluesky: #{e.class} - #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
    ensure
      # Always clean up video files to prevent accumulation
      if video_file_path
        begin
          File.unlink(video_file_path) if File.exist?(video_file_path)
        rescue => e
          Rails.logger.warn "Post: Failed to clean up video file #{video_file_path}: #{e.message}"
        end
      end
    end

    private

    def create_session
      return @bsky if @bsky # Return existing session if available
      return if Rails.env.test? # Skip actual creation in test environment
      return unless bluesky_enabled?

      validate_bluesky_credentials!

      credentials = ATProto::Credentials.new(bluesky_username, bluesky_app_password, bluesky_pds)
      session = ATProto::Session.new(credentials, false)
      open_atproto_session(session)
      @bsky = Bskyrb::Client.new(session)
    end

    def open_atproto_session(session)
      response = HTTParty.post(
        URI(session.create_session_uri(session.pds)),
        body: {identifier: session.credentials.username, password: session.credentials.pw}.to_json,
        headers: session.default_headers
      )

      raise ATProto::UnauthorizedError if response&.code == 401
      raise ATProto::HTTPError, "Bluesky createSession returned no response" unless response
      unless response.success?
        raise ATProto::HTTPError, "Bluesky createSession failed: #{response.code} #{response.message}"
      end

      access_token = response["accessJwt"]
      refresh_token = response["refreshJwt"]
      did = response["did"]
      unless access_token && refresh_token && did
        raise ATProto::HTTPError, "Bluesky createSession response missing required session fields"
      end

      session.instance_variable_set(:@access_token, access_token)
      session.instance_variable_set(:@refresh_token, refresh_token)
      session.instance_variable_set(:@did, did)
      session.instance_variable_set(:@service_endpoint, service_endpoint_for(session, response))
    end

    def service_endpoint_for(session, create_session_response)
      did_doc = create_session_response["didDoc"] || resolve_did_doc(session)
      endpoint = did_doc&.dig("service", 0, "serviceEndpoint")
      return "did:web:#{URI.parse(endpoint).host}" if endpoint

      "did:web:#{URI.parse(session.pds).host}"
    end

    def resolve_did_doc(session)
      response = HTTParty.get(
        URI("#{session.pds}/xrpc/com.atproto.identity.resolveDid?did=#{URI.encode_www_form_component(session.did)}"),
        headers: session.default_headers
      )

      return response["didDoc"] if response&.success? && response["didDoc"]

      Rails.logger.warn "Post: Bluesky didDoc missing from createSession and resolveDid failed; using PDS host for service auth audience"
      nil
    end

    def validate_bluesky_credentials!
      missing = []
      missing << "BLUESKY_USERNAME" if bluesky_username.empty?
      missing << "BLUESKY_APP_PASSWORD" if bluesky_app_password.empty?

      return if missing.empty?

      raise ArgumentError, "Missing required Bluesky configuration: #{missing.join(", ")}"
    end

    def bluesky_enabled?
      ENV["BLUESKY_ENABLED"] == "true"
    end

    def bluesky_username
      ENV["BLUESKY_USERNAME"].to_s.strip
    end

    def bluesky_app_password
      ENV["BLUESKY_APP_PASSWORD"].to_s.strip
    end

    def bluesky_pds
      ENV["BLUESKY_URL"].to_s.strip.presence || "https://bsky.social"
    end

    def append_team_hashtags(post)
      post += "\n#{ENV["TEAM_HASHTAGS"]}" if ENV["TEAM_HASHTAGS"]
      post
    end

    def create_post(post, embed_url: nil, embed_images: [], embed_video: nil)
      return unless ENV["BLUESKY_ENABLED"] == "true"

      # Filter out nil values from embed_images - Bsky client expects String (URL) or File objects only
      embed_images = Array(embed_images).compact

      @bsky.create_post(post, embed_url: embed_url, embed_images: embed_images, embed_video: embed_video)
    end

    def create_reply(reply_uri, post, embed_url: nil, embed_images: [], embed_video: nil)
      return unless ENV["BLUESKY_ENABLED"] == "true"

      # Filter out nil values from embed_images - Bsky client expects String (URL) or File objects only
      embed_images = Array(embed_images).compact

      Rails.logger.info "Creating reply to #{reply_uri} with post #{post} and embed_url #{embed_url}"
      @bsky.create_reply(reply_uri, post, embed_url: embed_url, embed_images: embed_images, embed_video: embed_video)
    end

    def log_post(post)
      Rails.logger.info "DEBUG: #{post}" if ENV["DEBUG_POSTS"] == "true"
    end

    def update_last_reply_tracker(root_key, reply_key)
      # Atomically update the last reply tracker for thread chaining
      # This happens after successful posting, ensuring correct order
      last_reply_tracker_key = "#{root_key}:last_reply_key"
      REDIS.set(last_reply_tracker_key, reply_key, ex: 172800)
      Rails.logger.info "Post: Updated last_reply_key tracker: #{last_reply_tracker_key} -> #{reply_key}"
    end
  end
end

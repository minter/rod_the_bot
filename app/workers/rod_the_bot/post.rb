module RodTheBot
  class Post
    include Sidekiq::Worker

    def perform(post)
      credentials = Bskyrb::Credentials.new(ENV["BLUESKY_USERNAME"], ENV["BLUESKY_APP_PASSWORD"])
      session = Bskyrb::Session.new(credentials, ENV["BLUESKY_URL"])
      @bsky = Bskyrb::RecordManager.new(session)
      post += "\n\n#{ENV["TEAM_HASHTAGS"]}"
      @bsky.create_post(post) if ENV["BLUESKY_ENABLED"] == "true"
      Rails.logger.info "DEBUG: #{post}" if ENV["DEBUG_POSTS"] == "true"
    end
  end
end

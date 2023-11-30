unless Rails.env.test?
  credentials = Bskyrb::Credentials.new(ENV["BLUESKY_USERNAME"], ENV["BLUESKYU_APP_PASSWORD"])
  session = Bskyrb::Session.new(credentials, ENV["BLUESKY_URL"])
  @bsky = Bskyrb::RecordManager.new(session)
end

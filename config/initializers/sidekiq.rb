if Rails.env.test?
  require "mock_redis"
  REDIS = MockRedis.new
else
  REDIS = Redis.new(url: ENV["REDIS_URL"])
end

Sidekiq.configure_server do |config|
  config.redis = Rails.env.test? ? {url: "redis://mock"} : {url: ENV["REDIS_URL"]}
end

Sidekiq.configure_client do |config|
  config.redis = Rails.env.test? ? {url: "redis://mock"} : {url: ENV["REDIS_URL"]}
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "vcr"
require "mocha/minitest"  # Add this line
require "sidekiq/testing"
require "mock_redis"

Sidekiq::Testing.fake!  # This puts Sidekiq into test mode

# Silence Sidekiq logging
Sidekiq.logger.level = Logger::ERROR

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers
  parallelize(workers: :number_of_processors)

  # Add more helper methods to be used by all tests here...

  setup do
    # Reset MockRedis before each test
    REDIS.flushdb
  end
end

VCR.configure do |config|
  config.cassette_library_dir = "fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.allow_http_connections_when_no_cassette = false
  # You can add more VCR configurations here if needed
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "sidekiq/testing"
require "vcr"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    Sidekiq::Testing.fake!

    ENV["TIME_ZONE"] = "America/New_York"
    # Add more helper methods to be used by all tests here...
  end
end

require "test_helper"

class RodTheBot::WorkerErrorHandlingTest < ActiveSupport::TestCase
  Worker = Class.new do
    include RodTheBot::WorkerErrorHandling

    def call(error)
      retry_job(error, game_id: 10, operation: "test")
    end
  end

  test "logs context and re-raises for Sidekiq" do
    error = Nhl::RequestError.new("timeout")
    Rails.logger.expects(:error).with do |message|
      message.include?("game_id=10") && message.include?("operation=test") && message.include?("Nhl::RequestError")
    end

    assert_same error, assert_raises(Nhl::RequestError) { Worker.new.call(error) }
  end

  test "logs permanent malformed input without raising" do
    Rails.logger.expects(:warn).with do |message|
      message.include?("game_id=10") && message.include?("discarded=missing details")
    end

    assert_nil Worker.new.send(:discard_job, "missing details", game_id: 10)
  end
end

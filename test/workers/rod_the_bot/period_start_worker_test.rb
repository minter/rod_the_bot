require "test_helper"
require "vcr"

class RodTheBot::PeriodStartWorkerTest < ActiveSupport::TestCase
  def setup
    @worker = RodTheBot::PeriodStartWorker.new
  end

  test "perform for first period" do
    game_id = "2023020341"
    VCR.use_cassette("nhl_gamecenter_pbp_#{game_id}") do
      play = {
        "periodDescriptor" => {"number" => 1, "periodType" => "REG"},
        "eventId" => 102
      }

      RodTheBot::GameStartWorker.expects(:perform_async).with(game_id)
      RodTheBot::Post.expects(:perform_async).never

      @worker.perform(game_id, play)
    end
  end

  test "perform for second period" do
    game_id = "2023020377"
    VCR.use_cassette("nhl_gamecenter_pbp_#{game_id}") do
      play = {
        "periodDescriptor" => {"number" => 2, "periodType" => "REG"},
        "eventId" => 123
      }

      RodTheBot::GameStartWorker.expects(:perform_async).never
      RodTheBot::Post.expects(:perform_async).with(regexp_matches(/🎬 It's time to start the 2nd Period/))

      @worker.perform(game_id, play)
    end
  end

  test "perform for overtime period" do
    game_id = "2023020341"
    VCR.use_cassette("nhl_gamecenter_pbp_#{game_id}") do
      play = {
        "periodDescriptor" => {"number" => 4, "periodType" => "OT"},
        "eventId" => 449
      }

      RodTheBot::GameStartWorker.expects(:perform_async).never
      RodTheBot::Post.expects(:perform_async).with(regexp_matches(/🎬 It's time to start the OT Period/))

      @worker.perform(game_id, play)
    end
  end

  test "perform for shootout" do
    game_id = "2023020341"
    VCR.use_cassette("nhl_gamecenter_pbp_#{game_id}") do
      play = {
        "periodDescriptor" => {"number" => 5, "periodType" => "SO"},
        "eventId" => 500
      }

      RodTheBot::GameStartWorker.expects(:perform_async).never
      RodTheBot::Post.expects(:perform_async).never

      @worker.perform(game_id, play)
    end
  end
end

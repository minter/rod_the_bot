require "test_helper"

VCR.configure do |config|
  config.cassette_library_dir = "fixtures/vcr_cassettes"
  config.hook_into :webmock
end

class RodTheBot::DivisionStandingsWorkerTest < Minitest::Test
  def setup
    ENV["NHL_TEAM_ABBREVIATION"] = "CAR"
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::DivisionStandingsWorker.new
  end

  def test_perform
    VCR.use_cassette("nhl_standings_now", allow_playback_repeats: true) do
      NhlApi.stub :preseason?, false do
        @worker.perform
        assert_equal 1, RodTheBot::Post.jobs.size

        expected_output = <<~POST
          📋 Here are the current standings for the Metropolitan division (by PT%):

          1. NYR: 31 pts (0.775%)
          2. CAR: 26 pts (0.619%)
          3. WSH: 22 pts (0.611%)
          4. NJD: 21 pts (0.525%)
          5. NYI: 22 pts (0.524%)
          6. PHI: 23 pts (0.523%)
          7. PIT: 21 pts (0.500%)
          8. CBJ: 18 pts (0.391%)
        POST

        assert_equal expected_output, RodTheBot::Post.jobs.first["args"].first
      end
    end
  end

  def test_sort_teams_in_division
    VCR.use_cassette("nhl_standings_now") do
      standings = NhlApi.fetch_standings["standings"]
      my_division = "Metropolitan"
      sorted_teams = @worker.send(:sort_teams_in_division, standings, my_division)

      assert_equal 8, sorted_teams.size
      assert_equal "NYR", sorted_teams.first["teamAbbrev"]["default"]
      assert_equal "CBJ", sorted_teams.last["teamAbbrev"]["default"]
    end
  end

  def test_format_standings
    VCR.use_cassette("nhl_standings_now") do
      standings = NhlApi.fetch_standings["standings"]
      my_division = "Metropolitan"
      division_teams = @worker.send(:sort_teams_in_division, standings, my_division)
      post = @worker.send(:format_standings, my_division, division_teams)

      expected_output = <<~POST
        📋 Here are the current standings for the Metropolitan division (by PT%):

        1. NYR: 31 pts (0.775%)
        2. CAR: 26 pts (0.619%)
        3. WSH: 22 pts (0.611%)
        4. NJD: 21 pts (0.525%)
        5. NYI: 22 pts (0.524%)
        6. PHI: 23 pts (0.523%)
        7. PIT: 21 pts (0.500%)
        8. CBJ: 18 pts (0.391%)
      POST

      assert_equal expected_output, post
    end
  end
end

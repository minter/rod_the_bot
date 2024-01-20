require "minitest/autorun"

VCR.configure do |config|
  config.cassette_library_dir = "fixtures/vcr_cassettes"
  config.hook_into :webmock
end

class DivisionStandingsWorkerTest < Minitest::Test
  def setup
    ENV["NHL_TEAM_ABBREVIATION"] = "CAR"
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::DivisionStandingsWorker.new
  end

  def test_perform
    VCR.use_cassette("nhl_standings_now") do
      @worker.perform
      assert_equal RodTheBot::Post.jobs.size, 1
    end
  end

  def test_find_my_division
    VCR.use_cassette("nhl_standings_now") do
      standings = @worker.send(:fetch_standings)
      my_division = @worker.send(:find_my_division, standings)
      assert_equal "Metropolitan", my_division
    end
  end

  def test_format_standings
    VCR.use_cassette("nhl_standings_now") do
      standings = @worker.send(:fetch_standings)
      my_division = @worker.send(:find_my_division, standings)
      division_teams = @worker.send(:sort_teams_in_division, standings, my_division)
      post = @worker.send(:format_standings, my_division, division_teams)
      expected_output = <<~POST
        📋 Here are the current standings for the Metropolitan division (by PT%):
        
        1. NYR: 31 pts (0.775 PT%)
        2. CAR: 26 pts (0.619 PT%)
        3. WSH: 22 pts (0.611 PT%)
        4. NJD: 21 pts (0.525 PT%)
        5. NYI: 22 pts (0.524 PT%)
        6. PHI: 23 pts (0.523 PT%)
        7. PIT: 21 pts (0.500 PT%)
        8. CBJ: 18 pts (0.391 PT%)
      POST
      assert_equal expected_output, post
    end
  end
end

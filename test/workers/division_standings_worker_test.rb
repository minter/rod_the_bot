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
        📋 Here are the current standings for the Metropolitan division:
        
        1. NYR: 31 pts (20 GP)
        2. CAR: 26 pts (21 GP)
        3. PHI: 23 pts (22 GP)
        4. NYI: 22 pts (21 GP)
        5. WSH: 22 pts (18 GP)
        6. PIT: 21 pts (21 GP)
        7. NJD: 21 pts (20 GP)
        8. CBJ: 18 pts (23 GP)
      POST
      assert_equal expected_output, post
    end
  end
end

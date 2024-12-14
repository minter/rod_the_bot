require "test_helper"

class RodTheBot::FinalScoreWorkerTest < ActiveSupport::TestCase
  def setup
    ENV["NHL_TEAM_ID"] = "12"
    ENV["WIN_CELEBRATION"] = "Canes Win"
    @worker = RodTheBot::FinalScoreWorker.new
    VCR.configure do |config|
      config.cassette_library_dir = "fixtures/vcr_cassettes"
      config.hook_into :webmock
    end
  end

  def test_perform
    VCR.use_cassette("nhl_game_boxscore_2024020448") do
      @worker.perform(2024020448)
      assert_not_empty @worker.feed
    end
  end

  def test_format_post
    VCR.use_cassette("nhl_game_boxscore_2024020448") do
      @worker.perform(2024020448)
      home = @worker.feed.fetch("homeTeam", {})
      visitor = @worker.feed.fetch("awayTeam", {})
      modifier = if @worker.feed.fetch("periodDescriptor", {}).fetch("periodType", "") == "SO"
        " (SO)"
      elsif @worker.feed.fetch("periodDescriptor", {}).fetch("periodType", "") == "OT"
        " (OT)"
      end
      home_team_is_yours = home.fetch("id", "").to_i == ENV["NHL_TEAM_ID"].to_i
      post = @worker.send(:format_post, home, visitor, modifier, home_team_is_yours)
      expected_output = <<~POST
        Canes Win
        
        Final Score:
        
        Sharks - 2 
        Hurricanes - 3
        
        Shots on goal:
        
        Sharks: 23
        Hurricanes: 28
      POST
      assert_equal expected_output, post
    end
  end

  def test_format_post_ot
    VCR.use_cassette("nhl_game_boxscore_2023020167") do
      @worker.perform(2023020167)
      home = @worker.feed.fetch("homeTeam", {})
      visitor = @worker.feed.fetch("awayTeam", {})
      modifier = if @worker.feed.fetch("periodDescriptor", {}).fetch("periodType", "") == "SO"
        " (SO)"
      elsif @worker.feed.fetch("periodDescriptor", {}).fetch("periodType", "") == "OT"
        " (OT)"
      end
      home_team_is_yours = home.fetch("id", "").to_i == ENV["NHL_TEAM_ID"].to_i
      post = @worker.send(:format_post, home, visitor, modifier, home_team_is_yours)
      expected_output = <<~POST
        Canes Win
        
        Final Score (OT):
        
        Hurricanes - 4 
        Islanders - 3
        
        Shots on goal:
        
        Hurricanes: 46
        Islanders: 25
      POST
      assert_equal expected_output, post
    end
  end

  def test_format_post_so
    VCR.use_cassette("nhl_game_boxscore_2023020032") do
      @worker.perform(2023020032)
      home = @worker.feed.fetch("homeTeam", {})
      visitor = @worker.feed.fetch("awayTeam", {})
      modifier = if @worker.feed.fetch("periodDescriptor", {}).fetch("periodType", "") == "SO"
        " (SO)"
      elsif @worker.feed.fetch("periodDescriptor", {}).fetch("periodType", "") == "OT"
        " (OT)"
      end
      home_team_is_yours = home.fetch("id", "").to_i == ENV["NHL_TEAM_ID"].to_i
      post = @worker.send(:format_post, home, visitor, modifier, home_team_is_yours)
      expected_output = <<~POST
        Canes Win
        
        Final Score (SO):
        
        Hurricanes - 6 
        Kings - 5
        
        Shots on goal:
        
        Hurricanes: 19
        Kings: 30
      POST
      assert_equal expected_output, post
    end
  end

  def test_format_post_loss
    VCR.use_cassette("nhl_game_boxscore_2023020034") do
      @worker.perform(2023020034)
      home = @worker.feed.fetch("homeTeam", {})
      visitor = @worker.feed.fetch("awayTeam", {})
      modifier = if @worker.feed.fetch("periodDescriptor", {}).fetch("periodType", "") == "SO"
        " (SO)"
      elsif @worker.feed.fetch("periodDescriptor", {}).fetch("periodType", "") == "OT"
        " (OT)"
      end
      home_team_is_yours = home.fetch("id", "").to_i == ENV["NHL_TEAM_ID"].to_i
      post = @worker.send(:format_post, home, visitor, modifier, home_team_is_yours)
      expected_output = <<~POST
        Final Score:
        
        Hurricanes - 3 
        Ducks - 6
        
        Shots on goal:
        
        Hurricanes: 35
        Ducks: 25
      POST
      assert_equal expected_output, post
    end
  end
end

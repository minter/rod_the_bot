require "test_helper"
require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = "fixtures/vcr_cassettes"
  config.hook_into :webmock
end

class GoalWorkerTest < Minitest::Test
  def setup
    Sidekiq::Worker.clear_all
    @goal_worker = RodTheBot::GoalWorker.new
    @game_id = "2023020339"
    @play_id = "240"
    ENV["NHL_TEAM_ID"] = "26"
  end

  def test_perform
    VCR.use_cassette("nhl_game_#{@game_id}_goal_play_#{@play_id}", allow_playback_repeats: true) do
      feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{@game_id}/play-by-play")
      play = feed["plays"].find { |play| play["eventId"].to_i == @play_id.to_i }

      @goal_worker.perform(@game_id, play)

      assert_equal 1, RodTheBot::Post.jobs.size
      assert_equal 1, RodTheBot::ScoringChangeWorker.jobs.size
      expected_output = <<~POST
        🎉 Kings GOOOOOOOAL!
        
        🚨 Arthur Kaliyev (5)
        🍎 Andreas Englund (6)
        🍎🍎 Jordan Spence (9)
        ⏱️  09:04 1st Period
        
        WSH 0 - LAK 1
      POST
      assert_equal expected_output, RodTheBot::Post.jobs.first["args"].first
    end
  end

  def test_build_players
    VCR.use_cassette("nhl_game_#{@game_id}_goal_play_#{@play_id}") do
      feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{@game_id}/play-by-play")
      players = @goal_worker.send(:build_players, feed)

      assert players.any?
      assert_equal players.first, [8471214, {team_id: 15, number: 8, name: "Alex Ovechkin"}]
      assert players.values.all? { |player| player[:team_id] && player[:number] && player[:name] }
    end
  end
end

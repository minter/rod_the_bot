class PenaltyWorkerTest < Minitest::Test
  def setup
    Sidekiq::Worker.clear_all
    @game_id = 2023020339
    @play_id = 377
    ENV["NHL_TEAM_ID"] = "99"
    @worker = RodTheBot::PenaltyWorker.new
  end

  def test_perform
    VCR.use_cassette("nhl_game_#{@game_id}_gamecenter_pbp_end_of_period_1") do
      @worker.perform(@game_id, @play_id)

      assert_equal 1, RodTheBot::Post.jobs.size
      expected_output = <<~POST
        🤩 Kings Penalty!
        
        Dylan Strome - Slashing
 
        That's a 2 minute Minor penalty at 18:25 of the 1st Period
      POST
      assert_equal expected_output, RodTheBot::Post.jobs.first["args"].first

      # Add assertions here based on what you expect to happen when perform is called
    end
  end

  def test_build_players
    VCR.use_cassette("nhl_game_#{@game_id}_gamecenter_pbp_end_of_period_1") do
      feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{@game_id}/play-by-play")
      players = @worker.send(:build_players, feed)

      assert players.any?
      assert_equal players.first, [8471214, {team_id: 15, number: 8, name: "Alex Ovechkin"}]
      assert players.values.all? { |player| player[:team_id] && player[:number] && player[:name] }

      # Add assertions here based on what you expect build_players to return
    end
  end
end

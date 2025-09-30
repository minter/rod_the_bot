require "test_helper"
require "vcr"
require "sidekiq/testing"

class RodTheBot::PenaltyWorkerTest < ActiveSupport::TestCase
  def setup
    @worker = RodTheBot::PenaltyWorker.new
    ENV["NHL_TEAM_ID"] = "12"  # Assuming this is the Carolina Hurricanes
    Sidekiq::Testing.fake!  # Enable fake Sidekiq queue
  end

  def teardown
    Sidekiq::Worker.clear_all  # Clear Sidekiq queue after each test
  end

  test "perform for various penalty types" do
    game_ids = ["2023020339", "2023020433"]

    game_ids.each do |game_id|
      VCR.use_cassette("nhl_game_#{game_id}_gamecenter_pbp", allow_playback_repeats: true) do
        feed = NhlApi.fetch_pbp_feed(game_id)
        penalty_plays = feed["plays"].select { |play| play["typeDescKey"] == "penalty" }

        penalty_plays.each do |play|
          VCR.use_cassette("nhl_api/player_#{play["details"]["committedByPlayerId"] || play["details"]["servedByPlayerId"]}_landing", allow_playback_repeats: true) do
            assert_difference -> { RodTheBot::Post.jobs.size }, 1 do
              @worker.perform(game_id, play)
            end

            # Verify the post content based on the play details
            expected_content = get_expected_content(play, feed)
            actual_content = RodTheBot::Post.jobs.last["args"].first
            assert_match expected_content, actual_content, "Expected content doesn't match actual content for play: #{play["eventId"]}"
          end
        end
      end
    end
  end

  private

  def get_expected_content(play, feed)
    home_team = feed["homeTeam"]
    away_team = feed["awayTeam"]
    your_team = (home_team["id"].to_s == ENV["NHL_TEAM_ID"]) ? home_team : away_team
    their_team = (your_team == home_team) ? away_team : home_team

    players = @worker.send(:build_players, feed)
    penalized_player = players[play["details"]["committedByPlayerId"]] || players[play["details"]["servedByPlayerId"]]

    penalized_team = (penalized_player && penalized_player[:team_id].to_s == ENV["NHL_TEAM_ID"]) ? your_team : their_team
    emoji = (penalized_team == your_team) ? "🙃" : "🤩"

    period_name = RodTheBot::PeriodFormatter.format_period_name(play["periodDescriptor"]["number"])

    player_name = penalized_player ? penalized_player[:name] : "Unknown Player"
    # Use the same penalty formatting logic as the worker
    desc_key = play["details"]["descKey"].sub(/^ps-/, "")
    penalty_desc = @worker.send(:format_penalty_name, desc_key)

    case play["details"]["typeCode"]
    when "BEN"
      /#{emoji} #{penalized_team["commonName"]["default"]} Penalty.*Bench Minor - #{penalty_desc}.*#{play["details"]["duration"]} minute penalty at #{play["timeInPeriod"]} of the #{period_name}/m
    when "PS"
      /#{emoji} #{penalized_team["commonName"]["default"]} Penalty.*#{player_name} - #{penalty_desc}.*penalty shot awarded at #{play["timeInPeriod"]} of the #{period_name}/m
    else
      /#{emoji} #{penalized_team["commonName"]["default"]} Penalty.*#{player_name} - #{penalty_desc}.*#{play["details"]["duration"]} minute #{RodTheBot::PenaltyWorker::SEVERITY[play["details"]["typeCode"]]} penalty at #{play["timeInPeriod"]} of the #{period_name}/m
    end
  end
end

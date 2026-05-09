require "test_helper"

class RodTheBot::ShotChartAnimator::ShotExtractorTest < ActiveSupport::TestCase
  SE = RodTheBot::ShotChartAnimator::ShotExtractor

  def test_extracts_only_shots_on_goal_and_goals_through_period
    feed = VCR.use_cassette("nhl_game_2024020477_gamecenter_pbp_end_of_period_1") do
      HTTParty.get("https://api-web.nhle.com/v1/gamecenter/2024020477/play-by-play")
    end

    shots = SE.call(feed: feed, through_period: 1)

    refute_empty shots
    assert(shots.all? { |s| %w[shot-on-goal goal].include?(s[:type]) },
           "extractor should keep only SOG and goals")
    assert(shots.all? { |s| s[:period] <= 1 },
           "should not include shots from later periods")
  end

  def test_drops_shots_with_missing_coordinates
    feed = {
      "homeTeam" => {"id" => 1, "abbrev" => "HME"},
      "awayTeam" => {"id" => 2, "abbrev" => "AWY"},
      "plays" => [
        {"typeDescKey" => "shot-on-goal",
         "periodDescriptor" => {"number" => 1},
         "timeInPeriod" => "01:00",
         "homeTeamDefendingSide" => "left",
         "details" => {"xCoord" => 10, "yCoord" => 5, "eventOwnerTeamId" => 1}},
        {"typeDescKey" => "shot-on-goal",
         "periodDescriptor" => {"number" => 1},
         "timeInPeriod" => "01:30",
         "homeTeamDefendingSide" => "left",
         "details" => {"eventOwnerTeamId" => 2}}
      ]
    }

    shots = SE.call(feed: feed, through_period: 1)
    assert_equal 1, shots.size
  end

  def test_normalizes_coords_for_period_where_home_defends_right
    feed = {
      "homeTeam" => {"id" => 1, "abbrev" => "HME"},
      "awayTeam" => {"id" => 2, "abbrev" => "AWY"},
      "plays" => [
        {"typeDescKey" => "shot-on-goal",
         "periodDescriptor" => {"number" => 2},
         "timeInPeriod" => "10:00",
         "homeTeamDefendingSide" => "right",
         "details" => {"xCoord" => 50, "yCoord" => 10, "eventOwnerTeamId" => 1}}
      ]
    }

    shots = SE.call(feed: feed, through_period: 2)
    assert_equal(-50, shots.first[:x])
    assert_equal(-10, shots.first[:y])
  end

  def test_sorts_chronologically_by_period_then_time
    feed = {
      "homeTeam" => {"id" => 1, "abbrev" => "HME"},
      "awayTeam" => {"id" => 2, "abbrev" => "AWY"},
      "plays" => [
        {"typeDescKey" => "shot-on-goal", "periodDescriptor" => {"number" => 2},
         "timeInPeriod" => "01:00", "homeTeamDefendingSide" => "left",
         "details" => {"xCoord" => 1, "yCoord" => 1, "eventOwnerTeamId" => 1}},
        {"typeDescKey" => "shot-on-goal", "periodDescriptor" => {"number" => 1},
         "timeInPeriod" => "19:00", "homeTeamDefendingSide" => "left",
         "details" => {"xCoord" => 2, "yCoord" => 2, "eventOwnerTeamId" => 2}},
        {"typeDescKey" => "shot-on-goal", "periodDescriptor" => {"number" => 1},
         "timeInPeriod" => "02:00", "homeTeamDefendingSide" => "left",
         "details" => {"xCoord" => 3, "yCoord" => 3, "eventOwnerTeamId" => 1}}
      ]
    }

    shots = SE.call(feed: feed, through_period: 2)
    assert_equal [[1, "02:00"], [1, "19:00"], [2, "01:00"]],
                 shots.map { |s| [s[:period], s[:time_in_period]] }
  end
end

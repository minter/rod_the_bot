require "test_helper"

class RodTheBot::PostseasonSeriesWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::PostseasonSeriesWorker.new
  end

  def test_fetch_current_series_stays_on_earlier_round_until_all_series_decided
    rounds = [
      round_data(1, "First Round", [
        series_data("AAA", 3, "BBB", 3), # still playing (best-of-7 not decided)
        series_data("CCC", 4, "DDD", 2)
      ]),
      round_data(2, "Second Round", [
        series_data("EEE", 0, "FFF", 0)
      ])
    ]

    picked = @worker.send(:fetch_current_series, rounds)
    assert_equal 1, picked["roundNumber"]
    assert_equal "First Round", picked["roundLabel"]
  end

  def test_fetch_current_series_advances_when_earlier_round_finished
    rounds = [
      round_data(1, "First Round", [
        series_data("AAA", 4, "BBB", 2),
        series_data("CCC", 4, "DDD", 1)
      ]),
      round_data(2, "Second Round", [
        series_data("AAA", 2, "CCC", 2)
      ])
    ]

    picked = @worker.send(:fetch_current_series, rounds)
    assert_equal 2, picked["roundNumber"]
  end

  def test_fetch_current_series_when_all_decided_shows_last_round
    rounds = [
      round_data(1, "First Round", [series_data("AAA", 4, "BBB", 2)]),
      round_data(4, "Stanley Cup Final", [series_data("AAA", 4, "CCC", 3)])
    ]

    picked = @worker.send(:fetch_current_series, rounds)
    assert_equal 4, picked["roundNumber"]
    assert_includes picked["roundLabel"], "Final"
  end

  def test_perform_skips_when_no_carousel
    NhlApi.expects(:fetch_postseason_carousel).returns(nil)
    @worker.perform
    assert_equal 0, RodTheBot::Post.jobs.size
  end

  def test_perform_posts_formatted_round
    carousel = {
      "rounds" => [
        round_data(1, "First Round", [
          series_data("CAR", 4, "FLA", 2)
        ])
      ]
    }
    NhlApi.expects(:fetch_postseason_carousel).returns(carousel)
    @worker.perform
    assert_equal 1, RodTheBot::Post.jobs.size
    post = RodTheBot::Post.jobs.first["args"].first
    assert_includes post, "First Round"
    assert_includes post, "CAR"
    assert_includes post, "FLA"
  end

  private

  def round_data(number, label, series_list)
    {"roundNumber" => number, "roundLabel" => label, "series" => series_list}
  end

  def series_data(top_abbrev, top_wins, bottom_abbrev, bottom_wins, needed: 4)
    {
      "neededToWin" => needed,
      "topSeed" => {"abbrev" => top_abbrev, "wins" => top_wins},
      "bottomSeed" => {"abbrev" => bottom_abbrev, "wins" => bottom_wins}
    }
  end
end

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
    NhlApi.expects(:playoff_seed_labels).returns({})
    @worker.perform
    assert_equal 1, RodTheBot::Post.jobs.size
    post = RodTheBot::Post.jobs.first["args"].first
    assert_includes post, "First Round"
    assert_includes post, "CAR"
    assert_includes post, "FLA"
  end

  def test_perform_includes_seed_labels
    carousel = {
      "rounds" => [
        round_data(1, "First Round", [
          series_data("BUF", 0, "BOS", 0)
        ])
      ]
    }
    NhlApi.expects(:fetch_postseason_carousel).returns(carousel)
    NhlApi.expects(:playoff_seed_labels).returns({"BUF" => "A1", "BOS" => "WC1"})
    @worker.perform
    post = RodTheBot::Post.jobs.first["args"].first
    assert_includes post, "(A1) BUF"
    assert_includes post, "(WC1) BOS"
  end

  def test_perform_filters_out_series_belonging_to_a_different_round
    carousel = {
      "rounds" => [
        round_data(2, "2nd-round", [
          series_data("BUF", 1, "MTL", 1),
          series_data("CAR", 4, "PHI", 0),
          series_data("TBD", 0, "CAR", 0, series_label: "conference-finals")
        ])
      ]
    }
    NhlApi.expects(:fetch_postseason_carousel).returns(carousel)
    NhlApi.expects(:playoff_seed_labels).returns({})
    @worker.perform
    post = RodTheBot::Post.jobs.first["args"].first
    assert_includes post, "BUF"
    assert_includes post, "CAR 4 - PHI 0"
    refute_includes post, "TBD"
  end

  def test_fetch_current_series_ignores_misrouted_series_when_deciding_round
    rounds = [
      round_data(2, "2nd-round", [
        series_data("AAA", 4, "BBB", 0),
        series_data("CCC", 4, "DDD", 1),
        series_data("TBD", 0, "AAA", 0, series_label: "conference-finals")
      ])
    ]

    picked = @worker.send(:fetch_current_series, rounds)
    assert_equal 2, picked["roundNumber"]
  end

  # Live NHL carousel from 2026-05-10: CAR had just clinched series J, and the API
  # leaked the conference-finals "M" slot (TBD vs CAR) into round 2's series list.
  # This cassette pins that exact shape so the regression can't sneak back in.
  def test_perform_with_live_round_two_carousel
    NhlApi.stubs(:current_season).returns("20252026")
    VCR.use_cassette("nhl_postseason_carousel_20252026_round2") do
      @worker.perform
    end

    assert_equal 1, RodTheBot::Post.jobs.size
    post = RodTheBot::Post.jobs.first["args"].first
    assert_includes post, "2nd Round"
    refute_includes post, "TBD"
    # The four real round-2 matchups should all be present.
    %w[BUF MTL CAR PHI COL MIN VGK ANA].each { |abbrev| assert_includes post, abbrev }
    # Exactly four matchup lines (one per series), beyond the header.
    assert_equal 4, post.scan(/\d+ - .* \d+/).length
  end

  def test_perform_handles_missing_seed_labels_gracefully
    carousel = {
      "rounds" => [
        round_data(1, "First Round", [
          series_data("CAR", 2, "OTT", 1)
        ])
      ]
    }
    NhlApi.expects(:fetch_postseason_carousel).returns(carousel)
    NhlApi.expects(:playoff_seed_labels).returns({})
    @worker.perform
    post = RodTheBot::Post.jobs.first["args"].first
    assert_includes post, "CAR 2 - OTT 1"
    refute_includes post, "()"
  end

  private

  def round_data(number, label, series_list)
    series_list = series_list.map { |s| s.merge("seriesLabel" => s["seriesLabel"] || label) }
    {"roundNumber" => number, "roundLabel" => label, "series" => series_list}
  end

  def series_data(top_abbrev, top_wins, bottom_abbrev, bottom_wins, needed: 4, series_label: nil)
    {
      "neededToWin" => needed,
      "seriesLabel" => series_label,
      "topSeed" => {"abbrev" => top_abbrev, "wins" => top_wins},
      "bottomSeed" => {"abbrev" => bottom_abbrev, "wins" => bottom_wins}
    }.compact
  end
end

require "test_helper"

class Nhl::RecordsClientTest < ActiveSupport::TestCase
  setup { Rails.cache.clear }

  test "normalizes franchise skater totals" do
    Nhl::RecordsClient.expects(:get_json).with do |path|
      path.start_with?("/skater-career-scoring-regular-season?") &&
        URI.decode_www_form(URI(path).query).to_h == {"cayenneExp" => "franchiseId=26"}
    end.returns("data" => [
      {"playerId" => 8446951, "firstName" => "Ron", "lastName" => "Francis", "goals" => 382, "assists" => 793, "points" => 1175, "activePlayer" => false}
    ])

    assert_equal(
      [{player_id: 8446951, name: "Ron Francis", goals: 382, assists: 793, points: 1175}],
      Nhl::RecordsClient.franchise_skater_totals(26)
    )
  end

  test "fetches real franchise totals" do
    VCR.use_cassette("nhl_records_franchise_skater_totals_26") do
      totals = Nhl::RecordsClient.franchise_skater_totals(26)
      francis = totals.find { |row| row[:player_id] == 8446951 }

      assert_operator totals.size, :>, 500
      assert_equal({player_id: 8446951, name: "Ron Francis", goals: 382, assists: 793, points: 1175}, francis)
    end
  end
end

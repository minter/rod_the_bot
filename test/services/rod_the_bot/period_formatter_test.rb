require "test_helper"

class RodTheBot::PeriodFormatterTest < ActiveSupport::TestCase
  include RodTheBot::PeriodFormatter

  test "format_period_name for regular periods" do
    assert_equal "1st Period", format_period_name(1)
    assert_equal "2nd Period", format_period_name(2)
    assert_equal "3rd Period", format_period_name(3)
  end

  test "format_period_name for overtime" do
    assert_equal "OT Period", format_period_name(4)
    assert_equal "2OT Period", format_period_name(5)
    assert_equal "3OT Period", format_period_name(6)
    assert_equal "10OT Period", format_period_name(13)
  end

  test "format_period_name with string input" do
    assert_equal "1st Period", format_period_name("1")
    assert_equal "OT Period", format_period_name("4")
    assert_equal "2OT Period", format_period_name("5")
  end

  test "format_period_name with invalid input" do
    assert_equal "Invalid Period", format_period_name(0)
    assert_equal "Invalid Period", format_period_name(-1)
  end

  test "ordinalize numbers" do
    assert_equal "1st", ordinalize(1)
    assert_equal "2nd", ordinalize(2)
    assert_equal "3rd", ordinalize(3)
    assert_equal "4th", ordinalize(4)
    assert_equal "11th", ordinalize(11)
    assert_equal "21st", ordinalize(21)
    assert_equal "102nd", ordinalize(102)
  end

  test "ordinalize with string input" do
    assert_equal "1st", ordinalize("1")
    assert_equal "22nd", ordinalize("22")
    assert_equal "103rd", ordinalize("103")
  end
end

module RodTheBot
  module PeriodFormatter
    extend self

    def format_period_name(period_number)
      period_number = period_number.to_i
      return "Invalid Period" if period_number < 1

      case period_number
      when 1..3
        "#{ordinalize(period_number)} Period"
      when 4
        "OT Period"
      else
        "#{period_number - 3}OT Period"
      end
    end

    def ordinalize(number)
      ActiveSupport::Inflector.ordinalize(number)
    end
  end
end

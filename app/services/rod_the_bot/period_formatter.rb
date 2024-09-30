module RodTheBot
  module PeriodFormatter
    extend self

    def format_period_name(period_number)
      case period_number.to_i
      when 1..3
        "#{ordinalize(period_number)} Period"
      when 4
        "OT Period"
      else
        "#{period_number.to_i - 3}OT Period"
      end
    end

    def ordinalize(number)
      ActiveSupport::Inflector.ordinalize(number)
    end
  end
end

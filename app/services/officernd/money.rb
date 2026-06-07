require "bigdecimal"

module Officernd
  # Converts money strings from a CSV into integer cents (the unit Jellyswitch stores).
  #
  #   Officernd::Money.to_cents("$1,234.56")            # => 123456
  #   Officernd::Money.to_cents("25", format: :cents)   # => 25
  #   Officernd::Money.to_cents("25", format: :dollars) # => 2500
  #
  # Default format is :dollars because human/CSV exports usually show dollars
  # ("25.00", "$25.00"). Use format: :cents when the column already holds integer cents
  # (e.g. a raw Stripe `amount_due`). The dry-run preview echoes parsed amounts so the
  # operator can sanity-check the interpretation before committing.
  module Money
    class ParseError < StandardError; end

    module_function

    def to_cents(value, format: :dollars)
      return nil if value.nil?

      str = value.to_s.strip
      return nil if str.empty?

      negative = str.start_with?("-") || (str.start_with?("(") && str.end_with?(")"))
      cleaned = str.gsub(/[()$,\s]/, "").sub(/\A-/, "")
      return nil if cleaned.empty?

      decimal = parse_decimal(cleaned, str)
      cents =
        case format.to_sym
        when :cents then decimal.round.to_i
        when :dollars then (decimal * 100).round.to_i
        else raise ArgumentError, "unknown money format: #{format.inspect}"
        end

      negative ? -cents : cents
    end

    def parse_decimal(cleaned, original)
      raise ParseError, "not a number: #{original.inspect}" unless cleaned.match?(/\A\d+(\.\d+)?\z/)

      BigDecimal(cleaned)
    end
  end
end

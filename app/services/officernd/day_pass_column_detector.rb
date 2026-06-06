module Officernd
  # Best-guess mapping of day-pass-CSV headers to canonical day-pass import fields.
  #
  #   Officernd::DayPassColumnDetector.detect(["Email", "Pass Type", "Date", "Complimentary"])
  #   # => { email: "Email", day_pass_type: "Pass Type", day: "Date", complimentary: "Complimentary" }
  class DayPassColumnDetector
    PATTERNS = {
      stripe_customer_id: [/\bstripe\b.*\b(customer|cus)\b/, /\bcustomer\s*id\b/, /\bcus_/],
      stripe_charge_id: [/\bstripe\b.*\bcharge\b/, /\bcharge\s*id\b/, /\bch_[A-Za-z0-9]/],
      email: [/\be-?mail\b/],
      day_pass_type: [/\bday\s*pass\s*type\b/, /\bpass\s*type\b/, /\bday\s*pass\b/, /\bpass\b/, /\btype\b/],
      complimentary: [/\bcomplimentary\b/, /\bcomp\b/, /\bfree\b/],
      day: [/\bday\s*pass\s*date\b/, /\bvisit\s*date\b/, /\bdate\b/, /\bday\b/, /\bvisit\b/],
    }.freeze

    FIELD_PRIORITY = %i[stripe_customer_id stripe_charge_id email day_pass_type complimentary day].freeze

    def self.detect(headers)
      new(headers).detect
    end

    def initialize(headers)
      @headers = Array(headers).map { |h| h.to_s.strip }.reject(&:empty?)
    end

    def detect
      taken = {}
      result = {}

      FIELD_PRIORITY.each do |field|
        header = best_header_for(field, exclude: taken.keys)
        next unless header

        result[field] = header
        taken[header] = field
      end

      result
    end

    private

    def best_header_for(field, exclude:)
      candidates = @headers - exclude
      PATTERNS.fetch(field).each do |pattern|
        ci = Regexp.new(pattern.source, Regexp::IGNORECASE)
        match = candidates.find { |h| ci.match?(h) }
        return match if match
      end
      nil
    end
  end
end

module Officernd
  # Best-guess mapping of CSV headers to canonical import fields, used to pre-fill the
  # column-mapping step of the onboarding wizard. The operator can override every guess.
  #
  #   Officernd::ColumnDetector.detect(["Full Name", "Email Address", "Stripe Customer"])
  #   # => { name: "Full Name", email: "Email Address", stripe_customer_id: "Stripe Customer" }
  #
  # Only headers that match are included; unmatched canonical fields are simply absent.
  class ColumnDetector
    # Canonical field => ordered list of matchers (Regexp, case-insensitive).
    # Earlier patterns win; more specific patterns are listed first.
    PATTERNS = {
      stripe_customer_id: [/\bstripe\b.*\b(customer|cus)\b/, /\bcustomer\s*id\b/, /\bcus_/],
      email: [/\be-?mail\b/],
      phone: [/\bphone\b/, /\bmobile\b/, /\btel\b/],
      name: [/\bfull\s*name\b/, /\b(member|contact)\s*name\b/, /\bname\b/],
      company: [/\bcompany\b/, /\bteam\b/, /\borganization\b/, /\borg\b/],
      membership: [/\bmembership\b/, /\bplan\b/, /\bsubscription\b/, /\bmember\s*type\b/],
      status: [/\bstatus\b/, /\bactive\b/, /\bstate\b/],
      start_date: [/\bstart\s*date\b/, /\bjoined\b/, /\bsince\b/],
    }.freeze

    # Order matters: assign more-specific fields first so a generic "name" pattern
    # can't steal the "company name" header before `company` gets a chance.
    FIELD_PRIORITY = %i[stripe_customer_id email phone company membership status start_date name].freeze

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

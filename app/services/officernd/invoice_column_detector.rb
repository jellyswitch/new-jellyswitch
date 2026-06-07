module Officernd
  # Best-guess mapping of invoice-CSV headers to canonical invoice import fields.
  # Mirrors ColumnDetector but tuned for an invoice/billing export. Operator overrides
  # every guess in the wizard.
  #
  #   Officernd::InvoiceColumnDetector.detect(["Invoice #", "Stripe Invoice", "Amount Due", "Status"])
  #   # => { number: "Invoice #", stripe_invoice_id: "Stripe Invoice",
  #   #      amount_due: "Amount Due", status: "Status" }
  class InvoiceColumnDetector
    PATTERNS = {
      stripe_invoice_id: [/\bstripe\b.*\binvoice\b/, /\binvoice\b.*\bstripe\b/, /\bin_[A-Za-z0-9]/],
      stripe_payment_intent_id: [/\bpayment\s*intent\b/, /\bpi_[A-Za-z0-9]/, /\bcharge\s*id\b/],
      stripe_customer_id: [/\bstripe\b.*\b(customer|cus)\b/, /\bcustomer\s*id\b/, /\bcus_/],
      email: [/\be-?mail\b/],
      number: [/\binvoice\s*(no|number|#)\b/, /\binvoice\s*#/, /\binvoice\s*id\b/, /\bnumber\b/],
      amount_paid: [/\bamount\s*paid\b/, /\bpaid\b/],
      amount_due: [/\bamount\s*due\b/, /\bamount\b/, /\btotal\b/, /\bsubtotal\b/],
      status: [/\bstatus\b/, /\bstate\b/],
      due_date: [/\bdue\s*date\b/, /\bdue\b/],
      date: [/\b(invoice|issue|created?)\s*date\b/, /\bdate\b/, /\bcreated\b/],
      description: [/\bdescription\b/, /\bmemo\b/, /\bline\s*items?\b/, /\bnotes?\b/],
    }.freeze

    # More-specific fields claim their header before generic ones.
    FIELD_PRIORITY = %i[
      stripe_invoice_id stripe_payment_intent_id stripe_customer_id email
      number amount_paid amount_due status due_date date description
    ].freeze

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

module Officernd
  # Normalizes assorted OfficeRnD/Stripe invoice status strings to the set Jellyswitch
  # understands: Invoice::STATUSES = %w(open uncollectible void paid refunded).
  #
  #   Officernd::InvoiceStatus.normalize("Past Due") # => "open"
  #   Officernd::InvoiceStatus.normalize("Paid")     # => "paid"
  #   Officernd::InvoiceStatus.normalize("weird")    # => nil  (caller warns + defaults)
  module InvoiceStatus
    DEFAULT = "open".freeze

    # Keys are in canonical "space form" (lowercased, _ and - become spaces).
    MAP = {
      "paid" => "paid",
      "open" => "open",
      "sent" => "open",
      "pending" => "open",
      "unpaid" => "open",
      "outstanding" => "open",
      "past due" => "open",
      "overdue" => "open",
      "uncollectible" => "uncollectible",
      "void" => "void",
      "voided" => "void",
      "cancelled" => "void",
      "canceled" => "void",
      "draft" => "void",
      "refunded" => "refunded",
      "refund" => "refunded",
    }.freeze

    module_function

    # Returns a canonical status, or nil if unrecognized.
    def normalize(raw)
      return nil if raw.nil?

      key = raw.to_s.strip.downcase.tr("_-", "  ").squeeze(" ").strip
      MAP[key]
    end
  end
end

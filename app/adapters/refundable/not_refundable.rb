module Refundable
  # Null-object for an invoice that can't be refunded — already refunded, void,
  # or otherwise neither voidable? nor paid?. Previously RefundableFactory.for
  # returned nil for this state and the caller did `nil.new(invoice)` (crash) or
  # called `.cancel` on nil, surfacing as a generic "An error occurred". Now the
  # factory hands back this object whose #cancel is a no-op returning false, so
  # Refunds::Save fails cleanly with a message instead of raising.
  class NotRefundable
    def initialize(invoice)
      @invoice = invoice
    end

    def cancel
      false
    end
  end
end

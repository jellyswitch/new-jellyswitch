
class RefundableFactory
  def self.for(invoice)
    klass = if invoice.voidable?
      Refundable::VoidableInvoice
    elsif invoice.paid?
      Refundable::RefundableInvoice
    else
      # Neither voidable nor paid (already refunded / void / nothing to collect).
      # Return a null-object instead of nil so callers never `nil.new` / `nil.cancel`.
      Refundable::NotRefundable
    end
    klass.new(invoice)
  end
end

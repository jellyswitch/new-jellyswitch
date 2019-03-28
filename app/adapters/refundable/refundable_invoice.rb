module Refundable
  class RefundableInvoice < SimpleDelegator
    def cancel
      stripe_refund = operator.create_stripe_refund(self)

      refunds.create(
        amount: amount_paid,
        user: user,
        stripe_refund_id: stripe_refund.id
      )

      update(status: 'refunded')
    end
  end
end

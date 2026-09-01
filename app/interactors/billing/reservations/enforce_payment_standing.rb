# Non-payment cutoff (PaymentCutoff): a member whose access is suspended for a
# still-unpaid invoice can't book rooms self-serve. Opt-in via
# enforce_payment_standing (mirrors enforce_posted_hours / enforce_coverage):
# admin and on-behalf flows don't set it, and payment_suspended? is itself
# false for staff. Runs FIRST — nothing persisted yet, nothing to roll back.
class Billing::Reservations::EnforcePaymentStanding
  include Interactor

  def call
    return unless context.enforce_payment_standing

    user = context.user
    return unless user&.payment_suspended?

    context.fail!(message: "Your account has a past-due balance, so booking is paused. Update your payment method to restore access instantly.")
  end
end

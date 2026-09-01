# Non-payment dunning policy (agreed 2026-09-01): when a member's auto-charged
# invoice fails, they get exactly three emails, then lose access until they pay.
#
#   1. FAILED_NOTICE     — immediately, from the invoice.payment_failed webhook
#                          (the existing "Action Required" email + push, now
#                          sent once per invoice instead of once per retry)
#   2. WARNING_NOTICE    — 48h later, via PaymentCutoffJob: "your access will
#                          be paused in 48 hours"
#   3. SUSPENSION_NOTICE — 48h after the warning: access is paused. From this
#                          moment User#payment_suspended? denies door unlock,
#                          the keys list, and member self-serve room booking.
#
# Each step is anchored to a ProductEmailSend row (sendable: the Invoice), so
# a step fires exactly once per invoice and never before its predecessor —
# nobody can be suspended without having been sent all three emails. Suspension
# is DERIVED (open invoice + suspension row), so paying the invoice by any path
# (Stripe retry, member Pay Now, admin retry) restores access instantly with no
# flag to reset. Individuals only: org-billed and out-of-band (net-30)
# billables never advance past step 1, and staff are exempt everywhere.
module PaymentCutoff
  FAILED_NOTICE     = "payment_cutoff_failed"
  WARNING_NOTICE    = "payment_cutoff_warning"
  SUSPENSION_NOTICE = "payment_cutoff_suspension"

  # Failure → warning, and warning → suspension. "3 emails in short order":
  # day 0, day 2, day 4 — then the doors close until the balance is settled.
  WARNING_AFTER = 48.hours
  SUSPEND_AFTER = 48.hours
end

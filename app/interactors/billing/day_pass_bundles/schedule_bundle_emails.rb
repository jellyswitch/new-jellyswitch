class Billing::DayPassBundles::ScheduleBundleEmails
  include Interactor

  # Onboarding only. The review (follow_up) and replenishment emails are
  # event-fired from the burn path (first redemption / zero balance), so
  # ScheduleProductEmails is told to skip the time-delayed follow_up for
  # day_pass_bundle. A bundle buyer is a customer, not a lead — so this stage
  # deliberately does NOT enroll them in the signup/welcome drip.
  def call
    context.product_email_sendable = context.day_pass_bundle
    context.product_email_type = "day_pass_bundle"
    context.product_email_user = context.day_pass_bundle&.user

    ScheduleProductEmails.call(context)
  end
end

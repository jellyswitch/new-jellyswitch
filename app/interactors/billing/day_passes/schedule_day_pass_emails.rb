class Billing::DayPasses::ScheduleDayPassEmails
  include Interactor

  def call
    context.product_email_sendable = context.day_pass
    context.product_email_type = "day_pass"
    context.product_email_user = context.day_pass&.user

    ScheduleProductEmails.call(context)
  end
end

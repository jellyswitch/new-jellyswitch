class Billing::Subscription::ScheduleSubscriptionEmails
  include Interactor

  def call
    context.product_email_sendable = context.subscription
    context.product_email_type = "membership"
    context.product_email_user = context.subscription&.subscribable

    ScheduleProductEmails.call(context)
  end
end

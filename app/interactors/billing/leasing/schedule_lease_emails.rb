class Billing::Leasing::ScheduleLeaseEmails
  include Interactor

  def call
    context.product_email_sendable = context.office_lease
    context.product_email_type = "office_lease"
    context.product_email_user = context.office_lease&.organization&.owner

    ScheduleProductEmails.call(context)
  end
end

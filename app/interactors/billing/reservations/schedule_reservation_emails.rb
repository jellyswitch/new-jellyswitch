class Billing::Reservations::ScheduleReservationEmails
  include Interactor

  def call
    context.product_email_sendable = context.reservation
    context.product_email_type = "reservation"
    context.product_email_user = context.reservation&.user

    ScheduleProductEmails.call(context)
  end
end

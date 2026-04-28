class Billing::Reservations::ExtendReservation
  include Interactor::Organizer

  # Extensions follow the same PaymentIntent hold flow as initial
  # bookings: AuthorizeHold cancels any prior hold and re-authorizes
  # for the new total max charge; CaptureHold settles at end_now or
  # via SettleReservationJob at the new datetime_out.
  organize(
    Billing::Reservations::UpdateReservationDuration,
    Billing::Reservations::ChargeCredits,
    Billing::Reservations::AuthorizeHold,
    Reservations::ScheduleSettleReservation,
  )
end

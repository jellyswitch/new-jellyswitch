class RemindUpcomingReservationJob < ApplicationJob
  queue_as :default

  def perform(reservation_id)
    upcoming_reservation = Reservation.find reservation_id
    room = upcoming_reservation.room

    reminder_time = upcoming_reservation.datetime_in - 10.minutes

    prior_reservation = room.reservations
      .where("datetime_in < ? AND datetime_in + (minutes * INTERVAL '1 minute') > ?", upcoming_reservation.datetime_in, reminder_time)
      .order(datetime_in: :desc)
      .first

    if prior_reservation
      SendNotificationsJob.perform_now(prior_reservation, "UpcomingReservationReminder")
    end
  end
end

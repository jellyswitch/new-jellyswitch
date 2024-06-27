class RemindUpcomingReservationJob < ApplicationJob
  queue_as :default

  def perform(reservation_id)
    upcoming_reservation = Reservation.find_by(id: reservation_id)

    if upcoming_reservation.nil? || upcoming_reservation.cancelled?
      Rails.logger.info("Upcoming reservation not found or cancelled: #{reservation_id}")
      return
    end

    prior_reservation = find_prior_reservation(upcoming_reservation)

    if prior_reservation
      SendNotificationsJob.perform_now(prior_reservation, "UpcomingReservationReminder")
    end
  end

  private

  def find_prior_reservation(upcoming_reservation)
    room = upcoming_reservation.room
    reminder_time = upcoming_reservation.datetime_in - Reservation::REMINDER_OFFSET_MINUTES

    room.reservations
      .where("datetime_in < ? AND datetime_in + (minutes * INTERVAL '1 minute') > ?", upcoming_reservation.datetime_in, reminder_time)
      .order(datetime_in: :desc)
      .first
  end
end

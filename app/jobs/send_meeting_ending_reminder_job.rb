class SendMeetingEndingReminderJob < ApplicationJob
  queue_as :default

  REMINDER_MINUTES_BEFORE_END = 10

  def perform(reservation_id)
    reservation = Reservation.find_by(id: reservation_id)
    return if reservation.nil? || reservation.cancelled?

    room = reservation.room
    user = reservation.user
    return unless user && room

    # Check if someone else has booked the room right after this reservation
    next_booking = room.reservations
      .where.not(id: reservation.id)
      .where(cancelled: false)
      .where("datetime_in >= ? AND datetime_in <= ?", reservation.datetime_out, reservation.datetime_out + 30.minutes)
      .order(:datetime_in)
      .first

    if next_booking
      # Room is booked after — tell them to wrap up
      message = "Your meeting in #{room.name} ends in #{REMINDER_MINUTES_BEFORE_END} minutes. #{next_booking.user&.name || 'Someone'} has the room after you — please prepare to wrap up."
    else
      # Room is free — offer to extend
      message = "Your meeting in #{room.name} ends in #{REMINDER_MINUTES_BEFORE_END} minutes. The room is available after — you can extend your booking if you need more time."
    end

    # Send push notification
    send_push(user, message, reservation)
  rescue => e
    Honeybadger.notify(e)
    Rails.logger.error("SendMeetingEndingReminderJob failed: #{e.class}: #{e.message}")
  end

  private

  def send_push(user, message, reservation)
    # iOS push
    if user.ios_token.present? && user.operator&.bundle_id.present?
      begin
        notification = IosNotification.new(
          token: user.ios_token,
          bundle_id: user.operator.bundle_id,
          message: message,
          data: { type: "reservation", resource_id: reservation.id, path: "/reservations/#{reservation.id}" }
        )
        notification.send_notification
      rescue => e
        Rails.logger.error("iOS push failed for meeting ending reminder: #{e.message}")
      end
    end

    # Android push
    if user.android_token.present?
      begin
        Notifiable::Default.new(nil).send_android_notification(
          user,
          "Meeting Ending Soon",
          message
        )
      rescue => e
        Rails.logger.error("Android push failed for meeting ending reminder: #{e.message}")
      end
    end
  end
end

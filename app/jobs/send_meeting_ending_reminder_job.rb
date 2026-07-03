class SendMeetingEndingReminderJob < ApplicationJob
  queue_as :default

  REMINDER_MINUTES_BEFORE_END = 10

  def perform(reservation_id)
    reservation = Reservation.find_by(id: reservation_id)
    return if reservation.nil? || reservation.cancelled?
    # `end_now!` (mobile "End Reservation" button + admin equivalents)
    # shortens `minutes` and sets `ended_early: true` — it does NOT set
    # `cancelled: true`. Without these guards the previously-scheduled
    # 10-min-before-end push fires at the original wait_until even though
    # the reservation is over. Skip if the user ended it early OR if the
    # current end time has already passed (defensive — covers extensions
    # that re-scheduled, manual datetime edits, or any other shortening).
    return if reservation.ended_early?
    return if reservation.datetime_out <= Time.current

    room = reservation.room
    user = reservation.user
    return unless user && room

    # Check if someone else has booked the room right after this reservation.
    next_booking = room.reservations
      .where.not(id: reservation.id)
      .where(cancelled: false)
      .where("datetime_in >= ? AND datetime_in <= ?", reservation.datetime_out, reservation.datetime_out + 30.minutes)
      .order(:datetime_in)
      .first

    message = if next_booking
      "Your meeting in #{room.name} ends in #{REMINDER_MINUTES_BEFORE_END} minutes. #{next_booking.user&.name || 'Someone'} has the room after you — please prepare to wrap up."
    else
      "Your meeting in #{room.name} ends in #{REMINDER_MINUTES_BEFORE_END} minutes. The room is available after — you can extend your booking if you need more time."
    end

    data = { screen: "MyReservations", type: "reservation", resource_id: reservation.id }

    send_ios(user, message, data)
    send_android(user, message, data)
  rescue => e
    Honeybadger.notify(e)
    Rails.logger.error("SendMeetingEndingReminderJob failed: #{e.class}: #{e.message}")
  end

  private

  def send_ios(user, message, data)
    return unless user.ios_token.present?
    return unless user.operator&.bundle_id.present?
    return unless ENV["APNS_KEY_FILE"].present? && ENV["APNS_KEY_ID"].present? && ENV["APNS_TEAM_ID"].present?

    IosNotification.new(user: user, message: message, data: data).send!
  rescue => e
    Rails.logger.error("iOS push failed for meeting ending reminder: #{e.message}")
    Honeybadger.notify(e)
  end

  def send_android(user, message, data)
    return unless user.android_token.present?
    operator = user.operator
    return unless operator&.android_push_notification_key&.attached?
    return unless operator.firebase_project_id.present?

    fcm = FCM.new('', StringIO.new(operator.android_push_notification_key.download), operator.firebase_project_id)
    payload = {
      token: user.android_token,
      notification: { title: "Meeting Ending Soon", body: message },
      # See Notifiable::Default#android_payload — expo-notifications only
      # exposes remote data to the JS tap handler from a JSON string under
      # the "body" key; flat keys never reach it.
      data: { "body" => data.to_json },
    }
    fcm.send_v1(payload)
  rescue => e
    Rails.logger.error("Android push failed for meeting ending reminder: #{e.message}")
    Honeybadger.notify(e)
  end
end

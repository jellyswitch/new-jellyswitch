class Reservations::MarkPaymentFailed
  include Interactor

  # Single chokepoint for "this reservation can't be paid for." Marks
  # the reservation, posts a feed item so admins see it in the
  # management feed, and emails the member with a "please update your
  # card" nudge. Idempotent — bails if payment_failed_at is already set.
  #
  # Called from:
  #   * AuthorizeReservationHoldJob (deferred-auth path failure)
  #   * Webhooks (Stripe upstream auto-cancel / payment-method failure)
  #   * CaptureHold (rescue branch on capture failure)
  delegate :reservation, :reason, to: :context

  def call
    return if reservation.nil?
    return if reservation.payment_failed_at.present?

    reservation.update!(payment_failed_at: Time.current)

    location = reservation.room.location
    operator = location.operator

    begin
      FeedItem.create!(
        operator: operator,
        location: location,
        user: reservation.user,
        blob: {
          'type' => 'payment_failed_room_reservation',
          'user_name' => reservation.user.name,
          'reservation_id' => reservation.id,
          'room_name' => reservation.room.name,
          'when' => reservation.pretty_datetime,
          'reason' => reason.to_s.first(200),
        },
      )
    rescue => e
      Rails.logger.error("MarkPaymentFailed feed item error: #{e.class}: #{e.message}")
      Honeybadger.notify(e, context: { reservation_id: reservation.id })
    end

    begin
      UserMailer.reservation_payment_failed(reservation.id, reason.to_s).deliver_later
    rescue => e
      Rails.logger.error("MarkPaymentFailed email error: #{e.class}: #{e.message}")
      Honeybadger.notify(e, context: { reservation_id: reservation.id })
    end
  end
end

class ScheduleProductEmails
  include Interactor

  def call
    sendable = context.product_email_sendable
    product_type = context.product_email_type
    user = context.product_email_user

    return unless sendable && product_type && user

    location = resolve_location(sendable, user)
    # Most callers (Billing::Reservations::CreateRoomReservation and friends)
    # never put operator on the context, so falling back to derive it from
    # the sendable / location keeps onboarding + follow-up emails firing.
    # Without this, every paid room reservation silently skipped its email.
    operator = context.operator || resolve_operator(sendable, location, user)

    return unless operator

    # Schedule onboarding email (immediate)
    onboarding_template = ProductEmailTemplate.find_by(
      operator: operator,
      location: location,
      product_type: product_type,
      email_type: "onboarding"
    )

    if onboarding_template&.enabled?
      SendProductEmailJob.perform_later(
        sendable.class.name,
        sendable.id,
        operator.id,
        product_type,
        "onboarding",
        user.id
      )
    end

    # Day Pass Bundle follow-up emails (review + replenishment) are event-fired
    # from the burn path, never on a purchase-time delay — so stop here for them.
    return if product_type == "day_pass_bundle"

    # Schedule follow-up email (delayed — timed from usage, not purchase)
    follow_up_template = ProductEmailTemplate.find_by(
      operator: operator,
      location: location,
      product_type: product_type,
      email_type: "follow_up"
    )

    if follow_up_template&.enabled?
      send_at = calculate_follow_up_time(sendable, product_type, follow_up_template)
      wait_duration = [send_at - Time.current, 0].max

      SendProductEmailJob.set(wait: wait_duration).perform_later(
        sendable.class.name,
        sendable.id,
        operator.id,
        product_type,
        "follow_up",
        user.id
      )
    end
  rescue => e
    # Don't fail the main transaction if email scheduling fails
    Honeybadger.notify(e)
    Rails.logger.error("ScheduleProductEmails failed: #{e.class}: #{e.message}")
  end

  private

  def resolve_location(sendable, user)
    case sendable
    when DayPass, DayPassBundle
      sendable.location
    when Reservation
      sendable.room&.location
    when OfficeLease
      sendable.location
    when Subscription
      sendable.plan&.location
    else
      Location.find_by(id: user.original_location_id)
    end
  end

  def resolve_operator(sendable, location, user)
    case sendable
    when DayPass, DayPassBundle, Subscription, OfficeLease
      sendable.operator
    when Reservation
      sendable.room&.location&.operator
    else
      location&.operator || user&.original_location&.operator
    end
  end

  def calculate_follow_up_time(sendable, product_type, template)
    delay_days = (template.follow_up_delay_days || 1).days
    timezone = resolve_timezone(sendable)

    case product_type
    when "day_pass"
      # Send at noon on the day pass date + delay days
      usage_date = sendable.day
      target_date = usage_date + (template.follow_up_delay_days || 1).days
      Time.use_zone(timezone) { Time.zone.local(target_date.year, target_date.month, target_date.day, 12, 0, 0) }

    when "reservation"
      # Send after the reservation ends + delay days
      reservation_end = sendable.datetime_in + sendable.minutes.minutes
      reservation_end + delay_days

    else
      # Office leases, memberships — delay from now (purchase time)
      Time.current + delay_days
    end
  end

  def resolve_timezone(sendable)
    tz = case sendable
         when DayPass
           sendable.location&.time_zone
         when Reservation
           sendable.room&.location&.time_zone
         end
    tz || "Pacific Time (US & Canada)"
  end
end

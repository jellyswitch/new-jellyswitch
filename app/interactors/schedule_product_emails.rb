class ScheduleProductEmails
  include Interactor

  def call
    sendable = context.product_email_sendable
    product_type = context.product_email_type
    user = context.product_email_user
    operator = context.operator

    return unless sendable && product_type && user && operator

    # Schedule onboarding email (immediate)
    onboarding_template = ProductEmailTemplate.find_by(
      operator: operator,
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

    # Schedule follow-up email (delayed — timed from usage, not purchase)
    follow_up_template = ProductEmailTemplate.find_by(
      operator: operator,
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

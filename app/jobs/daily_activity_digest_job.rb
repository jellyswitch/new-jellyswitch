class DailyActivityDigestJob < ApplicationJob
  queue_as :default

  def perform
    Operator.where(billing_state: "production").find_each do |operator|
      operator.locations.each do |location|
        next unless location.visible?

        Time.use_zone(location.time_zone) do
          generate_digest(operator, location)
        end
      end
    end
  end

  private

  def generate_digest(operator, location)
    day_passes = location.day_passes.today.includes(:user, :day_pass_type)
    reservations = Reservation.where(room: location.rooms).today.includes(:user, :room)
    paid_reservations = reservations.select(&:paid?)

    # Skip if nothing happening today
    return if day_passes.empty? && reservations.empty?

    # Calculate revenue
    paid_revenue = paid_reservations.sum { |r| r.room.hourly_rate_in_cents * (r.minutes / 60.0) / 100.0 }
    day_pass_revenue = day_passes.sum { |dp| dp.day_pass_type&.amount_in_cents.to_i / 100.0 }
    total_revenue = paid_revenue + day_pass_revenue

    # Build names list for day passers
    day_pass_names = day_passes.map { |dp| dp.user.name }

    # Create feed item
    blob = {
      type: "daily-digest",
      day_pass_count: day_passes.count,
      reservation_count: reservations.count,
      paid_reservation_count: paid_reservations.count,
      total_revenue_cents: (total_revenue * 100).round,
      day_pass_names: day_pass_names,
    }

    ActsAsTenant.with_tenant(operator) do
      feed_item = FeedItem.create!(
        operator: operator,
        location: location,
        blob: blob,
        created_at: Time.current
      )

      # Notify admins
      SendNotificationsJob.perform_later(feed_item)
    end
  end
end

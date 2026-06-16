class DailyActivityDigestJob < ApplicationJob
  queue_as :default

  def perform
    # Disabled: daily digest feed items had no useful display content
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
    # Exclude bundle-sourced entry passes: their day_pass_type.amount_in_cents
    # is the full N-Pack price (recognized once at purchase), so counting it per
    # entry would inflate day-pass revenue by the whole pack price each day.
    day_pass_revenue = day_passes.not_bundle_sourced.sum { |dp| dp.day_pass_type&.amount_in_cents.to_i / 100.0 }
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
      admin_user = User.relevant_admins_of_location(location).first
      return unless admin_user

      feed_item = FeedItem.create!(
        operator: operator,
        location: location,
        user: admin_user,
        blob: blob,
        created_at: Time.current
      )
    end
  end
end

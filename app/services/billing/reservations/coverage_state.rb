# Read-only classification of a member's day-pass coverage for booking an
# INCLUDED room on a given date (ADR 0019). Single source of truth shared by
# the eligibility preview and the booking-time enforcement.
class Billing::Reservations::CoverageState
  Result = Struct.new(:outcome, :passes_remaining, :bundle, :day_pass_type, :amount_cents, :reusable_pass,
                      keyword_init: true)

  def self.for(user:, room:, date:, location:)
    new(user: user, room: room, date: date.to_date, location: location).call
  end

  def initialize(user:, room:, date:, location:)
    @user = user
    @room = room
    @date = date
    @location = location
  end

  def call
    return Result.new(outcome: :not_applicable) unless included_room?
    return Result.new(outcome: :already_covered) if already_covered?

    if (spare = reusable_pass)
      return Result.new(outcome: :reusable_pass, reusable_pass: spare)
    end

    if (bundle = active_bundle)
      return Result.new(outcome: :bundle_available, bundle: bundle,
                        passes_remaining: active_bundles.sum(:passes_remaining))
    end

    type = suggested_day_pass_type
    Result.new(outcome: :needs_purchase, day_pass_type: type, amount_cents: type&.amount_in_cents)
  end

  private

  attr_reader :user, :room, :date, :location

  def included_room?
    room.hourly_rate_in_cents.to_i.zero? && room.include_with_day_pass?
  end

  # Mirrors reservations_controller#needs_cov (centralized).
  def already_covered?
    user.has_active_subscription? ||
      user.has_active_lease?(location) ||
      user.day_passes.for_location(location).for_day(date).exists? ||
      user.admin_or_manager?(location) ||
      user.superadmin?
  end

  # A purchased pass from a cancelled booking, still today-or-future, not the
  # requested date (that would be already_covered). Prefer the soonest such day.
  def reusable_pass
    user.day_passes.reusable_coverage(today)
        .where(location: location)
        .where.not(day: date)
        .order(:day)
        .first
  end

  # usable_on, not .active: coverage is FOR the requested date, and a pass may
  # not cover a date past its bundle's expiration (ADR 0018). A pack expiring
  # before the booked day previews as :needs_purchase — matching what
  # RedeemBundlePass will actually do — instead of offering a burn the booking
  # path must refuse.
  def active_bundles
    user.day_pass_bundles.usable_on(date, tz).where(location: location)
  end

  # Soonest-expiring, then oldest (ADR 0018 draw order — DayPassBundle.draw_order
  # is the single canonical definition; see its comment for why every caller
  # that picks "the" active bundle must share it).
  def active_bundle
    active_bundles.draw_order.first
  end

  # The same SKU the old silent auto-buy chose. Office-backed types are
  # excluded by KIND (was a %office% name-match) — an office pass is never
  # auto-suggested as mere room coverage (ADR 0026).
  def suggested_day_pass_type
    DayPassType.suggested_standard_for(location)
  end

  def today
    tz.today
  end

  def tz
    @tz ||= ActiveSupport::TimeZone[location&.time_zone.presence || "UTC"]
  end
end

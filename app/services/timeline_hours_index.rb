# Read-time "room hours booked" lookup for one page of a person's timeline.
#
# Reservation cards denormalize their own time into the activity payload
# (ADR-0001), but day-pass and bundle cards cannot: the hours accrue *after*
# the pass is bought, so they are only knowable when the card is rendered.
# This resolves the whole page in a fixed number of queries — bundles, their
# redemption days, then one pass over the member's reservations — so a 50-row
# timeline never becomes 50 lookups.
class TimelineHoursIndex
  EMPTY_BUNDLE = { quantity: 0, used: 0, minutes: 0 }.freeze

  def self.empty
    new({}, {})
  end

  def self.build(user:, activities:)
    day_pass_days = []
    bundle_ids    = []

    Array(activities).each do |activity|
      case activity.kind
      when "day_pass"
        day = parse_date(activity.payload&.dig("day"))
        day_pass_days << day if day
      when "day_pass_bundle"
        bundle_ids << activity.subject_id if activity.subject_id
      end
    end

    return empty if day_pass_days.empty? && bundle_ids.empty?

    bundles      = load_bundles(bundle_ids.uniq)
    bundle_days  = load_bundle_days(bundle_ids.uniq)
    minutes      = minutes_by_day(user, (day_pass_days + bundle_days.values.flatten).uniq)

    summaries = bundles.transform_values do |bundle|
      days = bundle_days[bundle[:id]] || []
      bundle.merge(minutes: days.sum { |day| minutes[day].to_i })
    end

    new(minutes, summaries)
  end

  def initialize(minutes_by_day, bundle_summaries)
    @minutes_by_day   = minutes_by_day
    @bundle_summaries = bundle_summaries
  end

  # Room minutes the member booked on that calendar day, in the room's zone.
  def minutes_on(day)
    @minutes_by_day[day].to_i
  end

  # { quantity:, used:, minutes: } for one bundle — zeroed if it is gone.
  def bundle(bundle_id)
    @bundle_summaries[bundle_id] || EMPTY_BUNDLE
  end

  def self.parse_date(value)
    value.presence && Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
  private_class_method :parse_date

  def self.load_bundles(ids)
    return {} if ids.empty?

    DayPassBundle.where(id: ids)
                 .pluck(:id, :quantity_purchased, :passes_remaining)
                 .each_with_object({}) do |(id, purchased, remaining), acc|
      acc[id] = { id: id, quantity: purchased.to_i, used: purchased.to_i - remaining.to_i }
    end
  end
  private_class_method :load_bundles

  # Only `entry` redemptions mint a day pass, and only those days can carry
  # room time — guest and admin_restore rows have no pass to book against.
  def self.load_bundle_days(ids)
    return {} if ids.empty?

    DayPassBundleRedemption.where(day_pass_bundle_id: ids, kind: "entry")
                           .where.not(day_pass_id: nil)
                           .joins(:day_pass)
                           .pluck(:day_pass_bundle_id, "day_passes.day")
                           .each_with_object(Hash.new { |h, k| h[k] = [] }) do |(bundle_id, day), acc|
      acc[bundle_id] << day
    end
  end
  private_class_method :load_bundle_days

  # Buckets in Ruby rather than SQL: Reservation#datetime_in already renders in
  # the room's location zone, so `.to_date` is the local calendar day. Doing the
  # same in SQL would need an AT TIME ZONE keyed off each row's own location.
  # The ±1 day fetch window absorbs every zone offset; anything that lands on a
  # day we were not asked about is dropped. Cancelled rows are excluded by
  # Reservation's default scope.
  def self.minutes_by_day(user, days)
    return {} if days.empty?

    wanted    = days.to_set
    condition = Array.new(days.size, "(reservations.datetime_in >= ? AND reservations.datetime_in < ?)").join(" OR ")
    bounds    = days.flat_map { |day| [day.to_time(:utc) - 1.day, day.to_time(:utc) + 2.days] }

    user.reservations
        .where(condition, *bounds)
        .includes(room: :location)
        .each_with_object(Hash.new(0)) do |reservation, acc|
      day = reservation.datetime_in.to_date
      acc[day] += reservation.minutes.to_i if wanted.include?(day)
    end
  end
  private_class_method :minutes_by_day
end

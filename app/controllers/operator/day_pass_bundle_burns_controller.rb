class Operator::DayPassBundleBurnsController < Operator::BaseController
  before_action :require_authentication

  # How far back staff can log a visit — ScheduleDay::HORIZON_DAYS pointing the
  # other way.
  LOOKBACK_DAYS = 90

  # Admin "Burn a pass" — spends one pass from a member's Day Pass Bundle for
  # today or a PAST day (e.g. an entry the door system missed). Auditable via
  # the admin_burn redemption row: redeemed_at carries the chosen day, the
  # reason lands in guest_name. No DayPass is minted, so nothing here grants
  # door access or reservation coverage. Future days go through "Use a pass"
  # (DayPassBundleSchedulesController), which DOES mint the dated pass.
  def create
    # friendly.find: nested user routes carry the friendly_id slug, not the id.
    user   = current_tenant.users.friendly.find(params[:user_id])
    # acts_as_tenant scopes DayPassBundle.find to current_tenant automatically.
    # Also scope to the member to prevent burning another user's bundle via this route.
    bundle = user.day_pass_bundles.find(params[:day_pass_bundle_id])

    unless current_user&.admin_or_manager?(current_location)
      return redirect_back fallback_location: user_day_passes_path(user),
                           alert: "Not authorized to burn a pass."
    end

    # BaseController's set_time_zone makes Time.zone the location's tz here.
    today = Time.zone.today
    day   = parse_day(params[:day], today)
    if day.nil?
      return burn_refused(user, "Could not read that date.")
    elsif day > today
      return burn_refused(user, "Pick today or a past day — future days go through \"Use a pass\".")
    elsif day < today - LOOKBACK_DAYS
      return burn_refused(user, "Pick a day within the last #{LOOKBACK_DAYS} days.")
    end

    # A day the member already had a pass, reservation, membership, or lease
    # for is already paid — burning it again would double-charge the pack.
    # Mirrors ScheduleDay#already_covered? (keep the two in sync).
    if covered?(user, day)
      return burn_refused(user, "#{user.name} already has coverage for #{day.strftime('%b %-d')} — nothing was burned.")
    end
    if pack_already_spent?(user, day)
      return burn_refused(user, "A pack pass was already used for #{day.strftime('%b %-d')} — nothing was burned.")
    end

    # Past burns stamp noon of the chosen day so the ledger row sits on the
    # visit's date (and the per-day guard above keys on it); today keeps "now".
    redeemed_at = day == today ? Time.current : Time.zone.local(day.year, day.month, day.day, 12)
    bundle.burn!(kind: :admin_burn, performed_by: current_user,
                 guest_name: params[:reason].presence, redeemed_at: redeemed_at)

    notice = "Burned a pass from #{user.name}'s bundle"
    notice += day == today ? "." : " for #{day.strftime('%b %-d')}."
    redirect_back fallback_location: user_day_passes_path(user), notice: notice
  rescue DayPassBundle::NoPassesRemaining
    redirect_back fallback_location: user_day_passes_path(user),
                  alert: "No passes left in that bundle."
  end

  private

  def burn_refused(user, message)
    redirect_back fallback_location: user_day_passes_path(user), alert: message
  end

  # Blank day = today, preserving the pre-date-picker behavior of the burn button.
  def parse_day(raw, today)
    return today if raw.blank?
    Date.parse(raw.to_s)
  rescue Date::Error, ArgumentError
    nil
  end

  def covered?(user, day)
    return true if user.has_active_subscription?
    return true if user.has_active_lease?(current_location)

    day_start = Time.zone.local(day.year, day.month, day.day)
    return true if user.reservations.where(cancelled: false)
                       .where(datetime_in: day_start..day_start.end_of_day).exists?

    user.day_passes.for_location(current_location).for_day(day).exists?
  end

  # One pack spend per day, across all the member's packs at this location.
  # Restore kinds (admin_restore / schedule_cancel) don't count — they return
  # passes, they don't spend them. Guest passes don't count either: a guest's
  # day is not the member's.
  def pack_already_spent?(user, day)
    day_start = Time.zone.local(day.year, day.month, day.day)
    DayPassBundleRedemption
      .where(day_pass_bundle_id: user.day_pass_bundles.where(location: current_location).select(:id))
      .where(kind: %w[entry reservation admin_burn])
      .where(redeemed_at: day_start..day_start.end_of_day)
      .exists?
  end
end

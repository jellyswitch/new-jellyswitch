module Permissions
  # Included as a module in the User class

  def allowed_in?(location)
    has_building_access_membership? ||
    has_active_day_pass_at_location?(location) ||
    checked_in?(location) ||
    has_active_lease? ||
    admin_of_location?(location) ||
    superadmin? ||
    has_active_reservation? ||
    has_rsvp?
  end

  def has_active_reservation?
    reservations.any? do |reservation|
      reservation.ongoing?
    end
  end

  def should_charge_for_reservation?(location, day = Time.current)
    if operator.production? || operator.subdomain == "southlakecoworking"
      # now adding community manager per https://github.com/jellyswitch/new-jellyswitch/commit/a3418b6a9f89562dba398f7920e7c7a7cede02a7 probably missed this
      !(member?(location) || has_purchased_day_pass?(day) || has_active_lease? || admin_of_location?(location) || superadmin? || general_manager_of_location?(location) || community_manager_of_location?(location))
    else
      false
    end
  end

  # Whether this user must pay the hourly rate for a specific ROOM at booking
  # time. Free rooms (rate 0) are never charged hourly. For premium/paid rooms
  # everyone pays EXCEPT members, leaseholders, and staff — note day-pass
  # holders are intentionally NOT exempt: a day pass covers free rooms +
  # included meeting-room minutes, not premium hourly rooms. (Same production
  # gate + exemptions as should_charge_for_reservation?, minus the day pass.)
  def should_charge_for_room?(room, day = Time.current)
    return false unless room.hourly_rate_in_cents.to_i > 0
    location = room.location
    if operator.production? || operator.subdomain == "southlakecoworking"
      !(member?(location) || has_active_lease? || admin_of_location?(location) || superadmin? || general_manager_of_location?(location) || community_manager_of_location?(location))
    else
      false
    end
  end

  def can_see_all_rooms?(location, day = Time.current)
    if operator.production? || operator.subdomain == "southlakecoworking"
      member?(location) ||
      has_active_day_pass?(day) ||
      checked_in?(location) ||
      has_active_lease? ||
      admin_of_location?(location)
    else
      true
    end
  end

  def has_rsvp?
    rsvps.going.today.count > 0
  end

  def member_at_operator?(operator, day = Time.current)
    has_active_subscription? || has_active_day_pass?(day = day) || has_active_lease?
  end

  # TODO: replace all `member_at_operator?` with this
  # Mainly for receiving notifications
  def member_at_location?(location, day = Time.current)
    current_location == location &&
    (
      has_active_subscription? || has_active_day_pass_at_location?(location, day = day) || has_active_lease?(location)
    )
  end

  def currently_at_location?(location)
    current_location == location
  end

  def member?(location, day = Time.current)
    has_active_subscription_at_location?(location)
  end

  # Paused subscriptions still have active=true on the AR row (the
  # `paused` flag is separate so Stripe can resume them later without
  # creating a new subscription). For ACCESS purposes — door punches,
  # room reservations, the "is this person currently a member" gate —
  # a paused sub should not count, otherwise members keep building
  # access after pausing.
  def has_active_subscription_at_location?(location)
    subscriptions.for_location(location).active.where(paused: false).select do |sub|
      sub.has_days_left?
    end.count > 0
  end

  # PLEEEASE REFRAIN FROM USING THIS METHOD, only when there is no location to be checked
  def admin?
    role == User::ADMIN || admin == true
  end

  def superadmin?
    role == User::SUPERADMIN || superadmin == true
  end

  def community_manager?
    role == User::COMMUNITY_MANAGER
  end

  def general_manager?
    role == User::GENERAL_MANAGER
  end

  def admin_or_manager?(location)
    admin_of_location?(location) || superadmin? || community_manager_of_location?(location) || general_manager_of_location?(location)
  end

  def pending?
    subscriptions.pending.count > 0
  end

  # Paused subscriptions excluded — see has_active_subscription_at_location?
  # for the full rationale. The `subscriptions.active` scope still
  # exists for billing-side use (Stripe sync, cancel flows) where
  # paused rows are still meaningful records.
  def has_active_subscription?
    subscriptions.for_operator(operator).active.where(paused: false).select do |sub|
      sub.has_days_left?
    end.count > 0
  end

  def has_building_access?(location)
    superadmin? ||
    admin_of_location?(location) ||
    community_manager_of_location?(location) ||
    general_manager_of_location?(location) ||
    always_allow_building_access? ||
    has_building_access_day_pass? ||
    has_building_access_membership? ||
    has_building_access_lease? ||
    has_active_day_pass_at_location?(location)
  end

  def has_building_access_membership?
    has_active_subscription? && subscriptions.active.where(paused: false).any? do |subscription|
      subscription.plan.always_allow_building_access?
    end
  end

  def has_active_day_pass?(day = Time.current)
    day_passes.for_day(day).count > 0
  end

  def has_purchased_day_pass?(day = Time.current)
    day_passes.for_day(day).purchased.count > 0
  end

  def has_active_day_pass_at_location?(location, day = Time.current)
    day_passes.for_location(location).for_day(day).count > 0
  end

  def has_building_access_day_pass?
    has_active_day_pass? && day_passes.today.any? do |day_pass|
      day_pass.day_pass_type.always_allow_building_access?
    end
  end

  def has_active_lease?(location = nil)
    has_active_org_lease?(location) || has_active_individual_lease?(location)
  end

  def has_building_access_lease?
    active_leases_for_access.any? { |lease| lease.always_allow_building_access? }
  end

  private

  def has_active_org_lease?(location = nil)
    organization.present? && organization.has_active_lease?(location)
  end

  def has_active_individual_lease?(location = nil)
    scope = OfficeLease.where(user_id: id).active
    scope = scope.where(location: location) if location.present?
    scope.exists?
  end

  def active_leases_for_access
    leases = []
    leases += organization.active_leases.to_a if organization.present?
    leases += OfficeLease.where(user_id: id).active.to_a
    leases
  end

  public

  def organization_owner?
    owned_organization.present?
  end

  def visible?
    !archived?
  end

  def member_of_organization?
    organization.present?
  end

  def authenticated?(remember_token)
    return false if remember_digest.nil?
    BCrypt::Password.new(remember_digest).is_password?(remember_token)
  end

  def has_profile_photo?
    profile_photo.attached?
  end

  def checked_in?(location)
    checkins.for_location(location).open.count > 0
  end

  def active_subscription_for_location(location)
    # Paused excluded — a paused member booking a room shouldn't get
    # their free-meeting-minutes allowance applied.
    subscriptions.active.where(paused: false).joins(:plan).find_by(plans: { location_id: location.id })
  end

  # Returns charge info for subscription members booking meeting rooms.
  # Returns nil if user has no active subscription or plan has no meeting room limit.
  # Otherwise returns a hash describing whether the booking is free or has overage.
  def subscription_reservation_charge_info(location, requested_minutes, room: nil)
    subscription = active_subscription_for_location(location)
    return nil unless subscription

    plan = subscription.plan
    return nil unless plan.has_meeting_room_limit?

    # Determine current billing cycle dates from Stripe
    period_start, period_end = subscription.current_billing_period
    return nil unless period_start

    # Sum non-cancelled reservation minutes in this billing cycle.
    # Only FREE (standard) rooms at THIS location burn the included pool:
    #   - paid/premium rooms are charged hourly separately, so their minutes
    #     must not eat the free allowance (mirrors the day-pass path), and
    #   - the allowance is location-specific, so bookings at the operator's
    #     other locations don't count against it.
    used_minutes = Reservation.joins(:room)
                              .where(user_id: id, cancelled: false)
                              .where(datetime_in: period_start..period_end)
                              .where("rooms.hourly_rate_in_cents = 0 OR rooms.hourly_rate_in_cents IS NULL")
                              .where(rooms: { location_id: location.id })
                              .sum(:minutes)

    remaining_free = [plan.included_meeting_room_minutes - used_minutes, 0].max

    if requested_minutes <= remaining_free
      {
        charge_type: :free,
        overage_minutes: 0,
        overage_minutes_rounded: 0,
        overage_amount_in_cents: 0,
        remaining_free: remaining_free,
        overage_rate_in_cents: plan.overage_rate_in_cents,
        used_minutes: used_minutes,
        included_minutes: plan.included_meeting_room_minutes
      }
    else
      overage_minutes = requested_minutes - remaining_free
      # Round up to nearest 15-minute increment (matches booking slider granularity)
      overage_minutes_rounded = (overage_minutes / 15.0).ceil * 15
      overage_amount = (plan.overage_rate_per_minute_in_cents * overage_minutes_rounded).to_i

      {
        charge_type: :partial_overage,
        overage_minutes: overage_minutes,
        overage_minutes_rounded: overage_minutes_rounded,
        overage_amount_in_cents: overage_amount,
        remaining_free: remaining_free,
        overage_rate_in_cents: plan.overage_rate_in_cents,
        used_minutes: used_minutes,
        included_minutes: plan.included_meeting_room_minutes
      }
    end
  end

  # Returns charge info for day pass users booking meeting rooms.
  # Returns nil if user is not a day pass holder or day pass has no meeting room limit.
  # Otherwise returns a hash describing whether the booking is free or has overage.
  def day_pass_reservation_charge_info(location, day, requested_minutes, room: nil)
    # Priced rooms (hourly_rate > 0) don't count toward day pass allowance.
    return nil if room && room.hourly_rate_in_cents.to_i > 0

    day = day.to_date if day.respond_to?(:to_date)
    return nil unless has_active_day_pass?(day)

    # Find the most generous day pass type (nil = unlimited first, then highest minutes)
    active_passes = day_passes.for_day(day).includes(:day_pass_type)
    day_pass = active_passes.sort_by { |dp|
      dp.day_pass_type.included_meeting_room_minutes || Float::INFINITY
    }.last
    return nil unless day_pass

    day_pass_type = day_pass.day_pass_type
    return nil unless day_pass_type.has_meeting_room_limit?

    # Calculate cumulative usage: sum of minutes from non-cancelled reservations for this user on this day
    # Priced rooms don't count toward day pass allowance
    used_minutes = Reservation.joins(:room).where(user_id: id, cancelled: false)
                              .where(datetime_in: day.beginning_of_day..day.end_of_day)
                              .where("rooms.hourly_rate_in_cents = 0 OR rooms.hourly_rate_in_cents IS NULL")
                              .sum(:minutes)

    remaining_free = [day_pass_type.included_meeting_room_minutes - used_minutes, 0].max

    if requested_minutes <= remaining_free
      {
        charge_type: :free,
        overage_minutes: 0,
        overage_minutes_rounded: 0,
        overage_amount_in_cents: 0,
        remaining_free: remaining_free,
        overage_rate_in_cents: day_pass_type.overage_rate_in_cents
      }
    else
      overage_minutes = requested_minutes - remaining_free
      # Round up to nearest 15-minute increment (matches booking slider granularity)
      overage_minutes_rounded = (overage_minutes / 15.0).ceil * 15
      overage_amount = (day_pass_type.overage_rate_per_minute_in_cents * overage_minutes_rounded).to_i

      {
        charge_type: :partial_overage,
        overage_minutes: overage_minutes,
        overage_minutes_rounded: overage_minutes_rounded,
        overage_amount_in_cents: overage_amount,
        remaining_free: remaining_free,
        overage_rate_in_cents: day_pass_type.overage_rate_in_cents
      }
    end
  end
end

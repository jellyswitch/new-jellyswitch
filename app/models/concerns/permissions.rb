module Permissions
  # Included as a module in the User class

  # Insider-status check — nav, landing, announcements, and room booking key
  # off it. NOT a door gate: DoorPolicy#open?/#keys? use
  # allowed_in_for_door_access? below, which bounds the day-pass and bundle
  # legs to posted hours (ADR 0023). Adding a leg here? Mirror it there.
  def allowed_in?(location)
    has_building_access_membership?(location) ||
    has_active_day_pass_at_location?(location) ||
    has_active_day_pass_bundle?(location) ||
    checked_in?(location) ||
    has_active_lease? ||
    admin_of_location?(location) ||
    superadmin? ||
    has_active_reservation? ||
    has_rsvp?
  end

  # The door-gate flavor of allowed_in?: same legs, except day-pass and
  # bundle access honor the location's posted hours (ADR 0023 — a pass
  # covers the DAY; the door only opens while the location is open), with
  # the always_allow_building_access pass-TYPE escape hatch. Closes the
  # legacy web open path (GET /doors/:slug/open), which stayed 24/7 after
  # the api/v1, web-XHR, and Keys-list gates were bounded. Membership,
  # lease, staff, checkin, reservation, and RSVP legs are unchanged.
  def allowed_in_for_door_access?(location)
    has_building_access_membership?(location) ||
    ((has_active_day_pass_at_location?(location) || has_active_day_pass_bundle?(location)) &&
      day_pass_within_posted_hours?(location)) ||
    has_building_access_day_pass?(location) ||
    has_building_access_day_pass_bundle?(location) ||
    checked_in?(location) ||
    has_active_lease? ||
    admin_of_location?(location) ||
    superadmin? ||
    has_active_reservation? ||
    has_rsvp?
  end

  def has_active_reservation?
    # SQL existence check (uses the [user_id, datetime_in] index) instead of
    # loading the member's entire reservation history into Ruby to scan with
    # ongoing? — this runs on nearly every access-policy check. The `ongoing`
    # scope and the ongoing? method agree on the underlying instant (start_at
    # round-trips the timezone), verified in reservation_ongoing_equivalence_spec;
    # using the scope also makes this consistent with everywhere else `.ongoing`
    # is used.
    reservations.ongoing.exists?
  end

  def should_charge_for_reservation?(location, day = Time.current)
    if operator.billing_state == "production"
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
    if operator.billing_state == "production"
      !(member?(location) || has_active_lease? || admin_of_location?(location) || superadmin? || general_manager_of_location?(location) || community_manager_of_location?(location))
    else
      false
    end
  end

  def can_see_all_rooms?(location, day = Time.current)
    if operator.production? || operator.subdomain == "southlakecoworking"
      member?(location) ||
      has_active_day_pass?(day) ||
      has_active_day_pass_bundle?(location) ||
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

  # Who may book a room outside the location's posted working hours
  # (working_day_start/end). Members get 24/7 self-service access — the
  # posted hours bound day-pass guests and the public, not paying members
  # or leaseholders. Superadmins are included for ops/off-hours bookings.
  # Used by the time_slots picker so an evening start isn't silently capped
  # at the close time. See the Drew Bray 30-min booking incident, 2026-06.
  def books_outside_posted_hours?(location)
    superadmin? ||
      has_active_subscription_at_location?(location) ||
      has_active_lease?(location)
  end

  # Paused subscriptions still have active=true on the AR row (the
  # `paused` flag is separate so Stripe can resume them later without
  # creating a new subscription). For ACCESS purposes — door punches,
  # room reservations, the "is this person currently a member" gate —
  # a paused sub should not count, otherwise members keep building
  # access after pausing.
  # Membership identity at a location. Deliberately NOT gated on the day-pool
  # limit (has_days_left?): a member who has used up their monthly days is still
  # a member with room access — running out of days revokes building access
  # only, on the access path below. See ADR 0004.
  def has_active_subscription_at_location?(location)
    # Nil when a multi-location operator has no location chosen yet — not a
    # member "nowhere in particular"; Subscription.for_location goes through
    # Plan.for_location, which derefs location.id.
    return false unless location

    subscriptions.for_location(location).active.where(paused: false).count > 0
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
  # Membership identity, operator-wide. NOT gated on the day-pool limit — see
  # has_active_subscription_at_location? and ADR 0004.
  def has_active_subscription?
    subscriptions.for_operator(operator).active.where(paused: false).count > 0
  end

  def has_building_access?(location)
    return true if superadmin? ||
                   admin_of_location?(location) ||
                   community_manager_of_location?(location) ||
                   general_manager_of_location?(location)

    # Approval is the hard gate for building access (Nash incident follow-up,
    # 2026-08-08) — same rule as Api::V1::DoorUnlocking#user_can_access_building?
    # so the web Keys list and the unlock path can't diverge (PR #668 invariant).
    return false unless approved?

    # Non-payment cutoff (PaymentCutoff) — same rule as the unlock path, for
    # the same lockstep reason: a payment-suspended member sees no keys on any
    # surface. Lifts itself the moment the past-due invoice is paid.
    return false if payment_suspended?

    always_allow_building_access? ||
    has_building_access_day_pass?(location) ||
    has_building_access_membership?(location) ||
    has_building_access_lease? ||
    # Day-pass access honors the location's posted hours (Nash, 2026-08-07).
    # 24/7 day-pass access exists only via an always_allow_building_access
    # pass TYPE — that's the has_building_access_day_pass? clause above.
    # Keeping the bound here (the web Keys list) in lockstep with the unlock
    # gate (Api::V1::DoorUnlocking) avoids re-opening the list/unlock
    # divergence PR #668 closed.
    (has_active_day_pass_at_location?(location) && day_pass_within_posted_hours?(location))
  end

  # Whether day-pass building access is currently inside the location's posted
  # hours — time-of-day only (within_posted_hours?), NOT the open_<day>
  # staffed-days flags: weekend daytime day-pass entry is established
  # behavior. Nil location keeps the previous behavior (no bound) rather than
  # locking members out on operators with no location context.
  def day_pass_within_posted_hours?(location, at = Time.current)
    location.nil? || location.within_posted_hours?(at)
  end

  # Building access via membership. This is where the day-pool limit gates:
  # a subscription only grants access while it has days left (has_days_left? is
  # itself scoped to the subscription's own location, so this stays correct for
  # members who roam between an operator's locations). A member out of days on
  # their only plan is blocked; a member with any other always-allow plan that
  # still has days left keeps access.
  # True if any active, non-paused membership grants building access to
  # `location` at time `at`, honoring the plan's building_access_level
  # (none / business_hours / all_hours), the day-pool limit, and — for the
  # business_hours tier — the location's posted hours. This is the SINGLE
  # source of truth shared by the Keys tab (has_building_access?) and the
  # door-unlock authorization (Api::V1::DoorUnlocking#user_can_access_building?)
  # so "what a member can see" and "what they can open" can never diverge.
  def has_building_access_membership?(location = current_location, at = Time.current)
    subscriptions.active.where(paused: false).any? do |subscription|
      subscription.has_days_left?(at) &&
        subscription.plan&.grants_building_access?(location, at)
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

  def has_active_day_pass_bundle?(location)
    return false unless location
    day_pass_bundles.active.where(location: location).exists?
  end

  # The always_allow_building_access pass-TYPE escape hatch (24/7 access).
  # Scoped to `location` when given — a 24/7 pass bought for one location
  # must not grant access at an operator's other locations. Lenient
  # for_location keeps legacy location-less passes working; callers with no
  # location context keep the old operator-wide behavior.
  def has_building_access_day_pass?(location = nil)
    passes = day_passes.today
    passes = passes.for_location(location) if location
    passes.any? { |day_pass| day_pass.day_pass_type.always_allow_building_access? }
  end

  # Bundle counterpart of has_building_access_day_pass?: an active bundle
  # whose pass TYPE is flagged always_allow_building_access keeps 24/7 door
  # access (same ADR 0023 escape hatch, same join as the api/v1 unlock gate).
  # Strictly location-scoped like has_active_day_pass_bundle? — bundles are
  # always stamped with a location.
  def has_building_access_day_pass_bundle?(location)
    return false unless location
    day_pass_bundles.active.where(location: location)
                    .joins(:day_pass_type)
                    .where(day_pass_types: { always_allow_building_access: true })
                    .exists?
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
    # Nil when a multi-location operator has no location chosen yet — not
    # checked in anywhere, rather than NoMethodError from Checkin.for_location
    # (which derefs location.id, unlike the nil-safe HasLocation scope).
    return false unless location

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
  def subscription_reservation_charge_info(location, requested_minutes, room: nil, at: Time.current)
    # Priced rooms (hourly_rate > 0) don't count toward subscription allowance.
    return nil if room && room.hourly_rate_in_cents.to_i > 0

    subscription = active_subscription_for_location(location)
    return nil unless subscription

    plan = subscription.plan
    return nil unless plan.has_meeting_room_limit?

    # Bill against the period the reservation FALLS IN (date-aware), so a
    # booking for next month draws from next month's fresh pool, not the
    # current one. Defaults to the current period for callers that don't
    # supply the reservation's date.
    period_start, period_end = subscription.billing_period_for(at)
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
                              .where(day_office_pass_id: nil) # office holds never draw the allowance (ADR 0026)
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

    # The included-minutes allowance comes from the day-pass type; the overage
    # RATE comes from the location (ADR 0012), so this quote agrees with the
    # amount ChargeCalculator captures. Only rooms flagged include_with_day_pass
    # draw down the allowance.
    overage_rate_in_cents = location.overage_rate_in_cents.to_i
    overage_rate_per_minute = overage_rate_in_cents / 60.0

    # Calculate cumulative usage: sum of minutes from non-cancelled reservations for this user on this day
    used_minutes = Reservation.joins(:room).where(user_id: id, cancelled: false)
                              .where(datetime_in: day.beginning_of_day..day.end_of_day)
                              .where(rooms: { include_with_day_pass: true })
                              .where(day_office_pass_id: nil) # office holds never draw the allowance (ADR 0026)
                              .sum(:minutes)

    remaining_free = [day_pass_type.included_meeting_room_minutes - used_minutes, 0].max

    if requested_minutes <= remaining_free
      {
        charge_type: :free,
        overage_minutes: 0,
        overage_minutes_rounded: 0,
        overage_amount_in_cents: 0,
        remaining_free: remaining_free,
        overage_rate_in_cents: overage_rate_in_cents
      }
    else
      overage_minutes = requested_minutes - remaining_free
      # Round up to nearest 15-minute increment (matches booking slider granularity)
      overage_minutes_rounded = (overage_minutes / 15.0).ceil * 15
      overage_amount = (overage_rate_per_minute * overage_minutes_rounded).to_i

      {
        charge_type: :partial_overage,
        overage_minutes: overage_minutes,
        overage_minutes_rounded: overage_minutes_rounded,
        overage_amount_in_cents: overage_amount,
        remaining_free: remaining_free,
        overage_rate_in_cents: overage_rate_in_cents
      }
    end
  end
end

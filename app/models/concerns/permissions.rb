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
      !(member?(location) || has_active_day_pass?(day) || has_active_lease? || admin_of_location?(location) || superadmin? || general_manager_of_location?(location) || community_manager_of_location?(location))
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

  def has_active_subscription_at_location?(location)
    subscriptions.for_location(location).active.select do |sub|
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

  def has_active_subscription?
    subscriptions.for_operator(operator).active.select do |sub|
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
    has_active_subscription? && subscriptions.active.any? do |subscription|
      subscription.plan.always_allow_building_access?
    end
  end

  def has_active_day_pass?(day = Time.current)
    day_passes.for_day(day).count > 0
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
    organization.present? && organization.has_active_lease?(location)
  end

  def has_building_access_lease?
    has_active_lease? && organization.active_leases.any? do |lease|
      lease.always_allow_building_access?
    end
  end

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

  # Returns charge info for day pass users booking meeting rooms.
  # Returns nil if user is not a day pass holder or day pass has no meeting room limit.
  # Otherwise returns a hash describing whether the booking is free or has overage.
  def day_pass_reservation_charge_info(location, day, requested_minutes)
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
    used_minutes = Reservation.where(user_id: id, cancelled: false)
                              .where(datetime_in: day.beginning_of_day..day.end_of_day)
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
      # Round up to nearest 30-minute increment
      overage_minutes_rounded = (overage_minutes / 30.0).ceil * 30
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

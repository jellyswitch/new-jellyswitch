module Permissions
  # Included as a module in the User class

  def allowed_in?(location)
    member?(location) ||
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
      !(member?(location) || has_active_day_pass?(day) || has_active_lease? || admin_of_location?(location) || superadmin? || general_manager?)
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
    admin_of_location?(location) || superadmin? || community_manager? || general_manager?
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
    community_manager? ||
    general_manager? ||
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
end

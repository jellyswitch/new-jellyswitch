module PolicyHelpers
  protected

  def is_user?
    user.present?
  end

  def location
    @location
  end

  def admin?
    is_user? && (((!location && user.admin?) || (location && user.admin_of_location?(location))) || user.superadmin?)
  end

  def general_manager?
    is_user? && ((!location && user.general_manager?) || (location && user.general_manager_of_location?(location)))
  end

  def community_manager?
    is_user? && ((!location && user.community_manager?) || (location && user.community_manager_of_location?(location)))
  end

  def superadmin?
    is_user? && user.superadmin?
  end

  def admin_or_manager?
    admin? || superadmin? || community_manager? || general_manager?
  end

  def checked_in?
    if @location.nil?
      false
    else
      is_user? && user.checked_in?(@location)
    end
  end

  def approved?
    is_user? && user.approved?
  end

  def owner?
    is_user? && (user == record.user)
  end

  def operator?
    admin? && (user.operator_id == record.id)
  end

  def billing_disabled?
    !billing_enabled?
  end

  def billing_enabled?
    operator.production? || operator.subdomain == "southlakecoworking"
  end

  def owner_or_admin?
    raise "Use individual permission predicates instead"
  end
end

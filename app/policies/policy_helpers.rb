module PolicyHelpers
  protected

  def is_user?
    user.present?
  end

  def admin?
    is_user? && (user.admin? || superadmin?)
  end

  def superadmin?
    is_user? && user.superadmin?
  end

  def member?
    if @operator.nil?
      raise "got here"
      false
    else
      is_user? && user.member?(@operator)
    end
  end

  def approved?
    is_user? && user.approved?
  end
  
  def owner?
    is_user? && (user == record.user)
  end
  
  def admin_or_member?
    raise "Use individual permission predicates instead"
  end

  def owner_or_admin?
    raise "Use individual permission predicates instead"
  end
end
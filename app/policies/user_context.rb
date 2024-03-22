
class UserContext
  attr_reader :user, :operator, :location

  def initialize(user, operator, location)
    @user = user
    @operator = operator
    @location = location
  end

  def admin?
    @user.admin?
  end

  def community_manager?
    @user.community_manager?
  end

  def general_manager?
    @user.general_manager?
  end

  def present?
    @user.present?
  end

  def superadmin?
    @user.superadmin?
  end

  def approved?
    @user.approved?
  end

  def requires_check_in?
    operator.checkin_required? && !user.checked_in?(location)
  end

  def pending?
    user.pending?
  end
end
class UserContext
  attr_reader :user, :operator

  def initialize(user, operator)
    @user = user
    @operator = operator
  end

  def admin?
    @user.admin?
  end

  def present?
    @user.present?
  end

  def superadmin?
    @user.superadmin?
  end
end
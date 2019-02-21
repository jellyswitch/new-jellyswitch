class UserContext
  attr_reader :user, :operator

  def initialize(user, operator)
    @user = user
    @operator = operator
  end
end
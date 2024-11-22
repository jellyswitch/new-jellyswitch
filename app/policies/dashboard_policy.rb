
class DashboardPolicy < Struct.new(:user, :dashboard)
  include PolicyHelpers

  def show?
    admin? || general_manager?
  end
end
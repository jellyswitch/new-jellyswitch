
class OnboardingPolicy < Struct.new(:user, :onboarding)
  include PolicyHelpers

  def show?
    (admin? || superadmin? || community_manager? || general_manager?)
  end
end

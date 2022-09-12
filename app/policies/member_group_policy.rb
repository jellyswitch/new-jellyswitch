# typed: ignore
class MemberGroupPolicy < ApplicationPolicy
  include PolicyHelpers

  def show?
    (admin? || community_manager? || general_manager?)
  end
end
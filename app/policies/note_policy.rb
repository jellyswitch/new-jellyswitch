class NotePolicy < ApplicationPolicy
  def create?
    can_see?
  end

  def destroy?
    return false unless can_see?
    record.author_id == user.id || admin? || superadmin?
  end

  def can_see?
    admin? || community_manager? || general_manager? || superadmin?
  end
end

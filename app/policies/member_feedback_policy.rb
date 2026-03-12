
class MemberFeedbackPolicy < ApplicationPolicy
  def new?
    is_user?
  end

  def create?
    is_user?
  end

  def index?
    (admin? || community_manager? || general_manager?)
  end

  def show?
    (admin? || community_manager? || general_manager?) || record_owner?
  end

  def reply?
    (admin? || community_manager? || general_manager?) || record_owner?
  end

  def my_feedback?
    is_user?
  end

  private

  def record_owner?
    if record.respond_to?(:user_id)
      record.user_id == user.id
    else
      true
    end
  end
end

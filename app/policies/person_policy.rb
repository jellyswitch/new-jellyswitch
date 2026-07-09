class PersonPolicy < ApplicationPolicy
  def index?
    admin? || community_manager? || general_manager? || superadmin?
  end

  # The office fairness queue, and working it one-by-one (offer / decline).
  def waitlist?
    admin_or_manager?
  end

  def office_outreach?
    admin_or_manager?
  end

  # Seed a draft campaign from the current People filter ("Message this list").
  def message_list?
    admin_or_manager?
  end
end

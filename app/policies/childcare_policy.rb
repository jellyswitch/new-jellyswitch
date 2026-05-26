
class ChildcarePolicy < ApplicationPolicy
  def enabled?
    # Nil-safe; see DoorPolicy#enabled? for the rationale.
    location&.childcare_enabled? || false
  end
end
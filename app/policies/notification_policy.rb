class NotificationPolicy < ApplicationPolicy
  def reservations?
    operator.reservation_notifications?
  end
end
# typed: true
class ScrubUser
  include Interactor
  include UsersHelper

  def call
    user = context.user

    ActiveRecord::Base.transaction do 
      user.reservations.future.each do |reservation|
        result = CancelReservation.call(
          reservation: reservation
        )
      end
    
      user.subscriptions.active.each do |subscription|
        result = CancelSubscription.call(
          subscription: subscription,
          creditable: subscription.subscribable
        )
      end

      result = ScrubUserData.call(
        user: user
      )

      user.day_passes.destroy_all
    end

    if !user.save
      context.fail!(message: "Unable to delete user account.")
    end
  end
end
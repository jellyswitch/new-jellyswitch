# typed: true
class ScrubUser
  include Interactor
  include UsersHelper

  def call
    user = context.user
    user_name = user.name

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

      result = FeedItems::Create.call(
        blob: { text: "#{user_name} deleted their account.", type: "post" },
        user: user,
        operator: user.operator,
        photos: []
      )

      result = ScrubUserData.call(
        user: user
      )
    end

    if !user.save
      context.fail!(message: "Unable to delete user account.")
    end
  end
end
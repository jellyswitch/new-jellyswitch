# typed: false
module Notifiable
  class ChildcareReservation < Notifiable::Default
    private

    def create_feed_item
      blob = {type: "childcare-reservation", childcare_reservation_id: id}
      FeedItemCreator.create_feed_item(child_profile.user.operator, child_profile.user, blob, created_at: created_at)
    end

    def should_send_notification?
      true
    end

    def send_notification
      message = "New childcare reservation for #{child_profile.name}"

      result = Notifications::PushNotifier.call(
        message: message,
        operator: child_profile.user.operator
      )

      if result.failure?
        Rollbar.error("Error pushing notification: #{result.message}")
      end
    end
  end
end

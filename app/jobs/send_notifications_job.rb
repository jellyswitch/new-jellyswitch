
class SendNotificationsJob < ApplicationJob
  queue_as :default

  def perform(notifiable, notifiable_type = nil)
    NotifiableFactory.for(notifiable, notifiable_type).notify
  end
end

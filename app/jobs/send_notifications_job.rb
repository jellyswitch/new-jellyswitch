
class SendNotificationsJob < ApplicationJob
  queue_as :default

  def perform(notifiable)
    NotifiableFactory.for(notifiable).notify
  end
end

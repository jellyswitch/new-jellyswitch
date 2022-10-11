
class SendNotificationsJob < ApplicationJob
  queue_as :default

  def perform(notifiable)
    
  end
end

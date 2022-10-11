
class CreateNotificationsAsync
  include Interactor

  delegate :notifiable, to: :context

  def call
    SendNotificationsJob.perform_later(notifiable)
  end
end

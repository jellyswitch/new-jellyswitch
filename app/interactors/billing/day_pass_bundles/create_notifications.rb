class Billing::DayPassBundles::CreateNotifications
  include Interactor

  delegate :notifiable, to: :context

  def call
    return if notifiable.blank?

    NotifiableFactory.for(notifiable).notify
  end
end

# typed: false
class NotifiableFactory
  def self.for(notifiable)
    case notifiable.class.name
    when 'Subscription'
      Notifiable::Subscription
    when 'DayPass'
      Notifiable::DayPass
    when 'Checkin'
      Notifiable::Checkin
    when 'WeeklyUpdate'
      Notifiable::WeeklyUpdate
    end.new(notifiable)
  end
end

# typed: false
class NotifiableFactory
  def self.for(notifiable)
    case notifiable.class.name
    when 'Announcement'
      Notifiable::Announcement
    when 'Checkin'
      Notifiable::Checkin
    when 'DayPass'
      Notifiable::DayPass
    when 'Subscription'
      Notifiable::Subscription
    when 'WeeklyUpdate'
      Notifiable::WeeklyUpdate
    end.new(notifiable)
  end
end

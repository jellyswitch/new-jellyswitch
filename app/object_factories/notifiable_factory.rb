# typed: false
class NotifiableFactory
  def self.for(notifiable)
    case notifiable.class.name
    when 'Announcement'
      Notifiable::Announcement
    when 'Checkin'
      Notifiable::Checkin
    when 'ChildcareReservation'
      Notifiable::ChildcareReservation
    when 'DayPass'
      Notifiable::DayPass
    when 'MemberFeedback'
      Notifiable::MemberFeedback
    when 'Reservation'
      Notifiable::Reservation
    when 'Subscription'
      Notifiable::Subscription
    when 'User'
      Notifiable::User
    when 'WeeklyUpdate'
      Notifiable::WeeklyUpdate
    end.new(notifiable)
  end
end

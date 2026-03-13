class NotifiableFactory
  def self.for(notifiable, notifiable_type = nil)
    type = notifiable_type || notifiable.class.name

    case type
    when "Announcement"
      Notifiable::Announcement
    when "Checkin"
      Notifiable::Checkin
    when "ChildcareReservation"
      Notifiable::ChildcareReservation
    when "DayPass"
      Notifiable::DayPass
    when "FeedItem"
      Notifiable::FeedItem
    when "FeedItemComment"
      Notifiable::FeedItemComment
    when "FeedbackReply"
      Notifiable::FeedbackReply
    when "MemberFeedback"
      Notifiable::MemberFeedback
    when "Post"
      Notifiable::Post
    when "PostReply"
      Notifiable::PostReply
    when "Reservation"
      Notifiable::Reservation
    when "Subscription"
      Notifiable::Subscription
    when "User"
      Notifiable::User
    when "WeeklyUpdate"
      Notifiable::WeeklyUpdate
    when "PaidRoomReservation"
      Notifiable::PaidRoomReservation
    when "UpcomingReservationReminder"
      Notifiable::UpcomingReservationReminder
    when "ReservationReminder"
      Notifiable::ReservationReminder
    when "Approval"
      Notifiable::Approval
    else
      raise "Unknown notifiable type: #{type}"
    end.new(notifiable)
  end
end

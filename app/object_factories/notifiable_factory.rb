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
    when "DayPassBundle"
      Notifiable::DayPassBundle
    when "Event"
      Notifiable::Event
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
    when "ReservationStarted"
      Notifiable::ReservationStarted
    when "ReservationCharged"
      Notifiable::ReservationCharged
    when "Approval"
      Notifiable::Approval
    when "RoomDemandMiss"
      Notifiable::DemandMiss
    when "PointOfContactAlert"
      Notifiable::PointOfContactAlert
    when "TourRequestAlert"
      Notifiable::TourRequestAlert
    when "OfficeVacancy"
      Notifiable::OfficeVacancy
    # Day Office (ADR 0026). All five wrap an existing record and are always
    # dispatched with an explicit type string, so none of them can be reached
    # by the bare-class branch above.
    when "DayOfficeAssigned"
      Notifiable::DayOfficeAssigned
    when "DayOfficeUnavailable"
      Notifiable::DayOfficeUnavailable
    when "DayOfficeUnassignedAlert"
      Notifiable::DayOfficeUnassignedAlert
    when "DayOfficeUnassignedBookingAlert"
      Notifiable::DayOfficeUnassignedBookingAlert
    when "DayOfficeReassigned"
      Notifiable::DayOfficeReassigned
    when "PaymentFailed"
      Notifiable::PaymentFailed
    else
      raise "Unknown notifiable type: #{type}"
    end.new(notifiable)
  end
end

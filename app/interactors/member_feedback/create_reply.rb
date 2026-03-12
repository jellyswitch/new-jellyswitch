class MemberFeedback::CreateReply
  include Interactor::Organizer

  organize(
    MemberFeedback::SaveReply,
    CreateNotifications
  )
end

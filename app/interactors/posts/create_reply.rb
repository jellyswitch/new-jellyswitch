class Posts::CreateReply
  include Interactor::Organizer

  organize(
    Posts::SaveReply,
    CreateNotificationsAsync
  )
end

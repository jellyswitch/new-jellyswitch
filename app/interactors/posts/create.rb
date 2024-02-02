class Posts::Create
  include Interactor::Organizer

  organize(
    Posts::Save,
    CreateNotificationsAsync
  )
end
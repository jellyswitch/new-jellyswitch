class FeedItems::Create
  include Interactor::Organizer

  organize(
    FeedItems::Save,
    CreateNotificationsAsync
  )
end
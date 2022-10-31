class Announcements::Create
  include Interactor::Organizer

  organize(
    Announcements::Save,
    FeedItems::Save,
    Announcements::SendEmail,
    CreateNotificationsAsync
  )
end
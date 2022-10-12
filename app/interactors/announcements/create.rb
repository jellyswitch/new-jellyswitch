class Announcements::Create
  include Interactor::Organizer

  organize(
    Announcements::Save,
    Announcements::SendEmail,
    CreateNotificationsAsync
  )
end
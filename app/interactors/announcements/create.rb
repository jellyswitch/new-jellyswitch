class Announcements::Create
  include Interactor::Organizer

  organize(
    Announcements::Save,
    CreateNotifications
  )
end
class WeeklyUpdates::Create
  include Interactor::Organizer

  organize(
    WeeklyUpdates::Save
  )
end
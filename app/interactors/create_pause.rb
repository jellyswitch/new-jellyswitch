class CreatePause
  include Interactor::Organizer

  organize(
    FeedItems::Create,
    PauseMembership,
  )
end
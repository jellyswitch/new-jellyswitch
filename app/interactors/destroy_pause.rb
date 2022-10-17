class DestroyPause
  include Interactor::Organizer

  organize(
    FeedItems::Create,
    UnpauseMembership,
  )
end
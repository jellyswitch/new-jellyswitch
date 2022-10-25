class UpdateMembership
  include Interactor::Organizer

  organize(
    SwitchMembership,
    FeedItems::Create,
    )
end
class Demo::Recreate::Members
  include Interactor::Organizer

  organize(
    Demo::Recreate::CreateMembers,
    # Demo::Recreate::Reservations,
    # Demo::Recreate::MemberFeedbacks,
    # Demo::Recreate::Announcements,
    # Demo::Recreate::Events,
    # Demo::Recreate::DoorPunches,
    # Demo::Recreate::FeedItems,
    # Demo::Recreate::FeedItemComments,
  )
end
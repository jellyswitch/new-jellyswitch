class Demo::Clean
  include Interactor::Organizer

  organize(
    Demo::SelectOperator,
    Demo::Clean::Invoices, # TODO (Leases, Checkins, Memberships, Day Passes, Refunds, Invoices)
    Demo::Clean::Organizations, # TODO
    Demo::Clean::Members,
    Demo::Clean::Offices,
    Demo::Clean::Rooms,
    Demo::Clean::Doors,
    Demo::Clean::Plans,
    Demo::Clean::DayPassTypes,
    Demo::Clean::WeeklyUpdates, # TODO
    Demo::Clean::Locations,
    Demo::Recreate::Locations,
    Demo::Recreate::DayPassTypes,
    Demo::Recreate::Plans,
    Demo::Recreate::Doors,
    Demo::Recreate::Rooms,
    Demo::Recreate::Offices,
    Demo::Recreate::Members
  )

end
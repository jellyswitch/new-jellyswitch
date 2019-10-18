class Demo::Clean
  include Interactor::Organizer

  organize(
    Demo::SelectOperator,
    Demo::Clean::Invoices, # TODO (Leases, Checkins, Memberships, Day Passes, Refunds, Invoices)
    Demo::Clean::Organizations, # TODO
    Demo::Clean::Members, # TODO (Members, Reservations, Feedbacks, Announcements, Events, Door Punches, Feed Items, Feed Item Comments)
    Demo::Clean::Offices, # TODO
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
  )

end
class Demo::Clean
  include Interactor::Organizer

  organize(
    Demo::SelectOperator,
    Demo::Clean::Invoices,
    Demo::Clean::Organizations,
    Demo::Clean::Members,
    Demo::Clean::Offices,
    Demo::Clean::Rooms,
    Demo::Clean::Doors,
    Demo::Clean::Plans,
    Demo::Clean::DayPassTypes,
    Demo::Clean::WeeklyUpdates,
    Demo::Clean::Locations,
    Demo::Recreate::Locations,
  )

end
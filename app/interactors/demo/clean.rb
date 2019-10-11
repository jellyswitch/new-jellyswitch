class Demo::Clean
  include Interactor::Organizer

  organize(
    Demo::SelectOperator,
    Demo::Clean::Invoices,
    Demo::Clean::Organizations,
    Demo::Clean::Members
  )

end
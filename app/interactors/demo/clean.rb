class Demo::Clean
  include Interactor::Organizer

  organize(
    Demo::SelectOperator,
    Demo::Clean::Invoices
  )

end
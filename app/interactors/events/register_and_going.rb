class Events::RegisterAndGoing
  include Interactor::Organizer

  organize(
    Events::CreateUser,
    Events::Going
  )
end
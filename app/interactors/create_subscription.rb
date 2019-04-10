class CreateSubscription
  include Interactor::Organizer

  organize UpdateUserPayment, SaveSubscription
end

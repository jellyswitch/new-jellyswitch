
class Checkins::Checkout
  include Interactor::Organizer

  organize(
    Checkins::SaveCheckout,
    Checkins::CreateStripeInvoice
  )
end
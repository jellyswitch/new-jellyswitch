# Only used for organization creation in app/interactors/create_organization.rb
class Billing::Payment::CreateStripeCustomer
  include Interactor

  delegate :billable, :operator, :location, to: :context

  def call
    return if billable.stripe_customer_id
    stripe_customer = location.create_stripe_customer(billable)
    billable.update(stripe_customer_id: stripe_customer.id)
  end
end

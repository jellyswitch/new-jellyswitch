class UpdateOrganizationBilling
  include Interactor

  delegate :organization, :stripe_token, to: :context

  def call
    stripe_customer = organization.find_or_create_stripe_customer

    stripe_customer.source = stripe_token
    organization.stripe_customer_id = stripe_customer.id

    unless stripe_customer.save && organization.save
      context.fail!(message: "Unable to update billing info.")
    end
  end
end

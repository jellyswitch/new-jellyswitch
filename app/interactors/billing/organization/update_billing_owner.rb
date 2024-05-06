class Billing::Organization::UpdateBillingOwner
  include Interactor

  delegate :organization, :new_billing_owner, :operator, to: :context

  def call
    begin
      operator.update_customer_email(organization, new_billing_owner.email)
    rescue StandardError => e
      context.fail!(message: "Failed to update billing owner: #{e.message}")
    end
  end
end

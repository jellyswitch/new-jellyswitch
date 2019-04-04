class Operator::OrganizationBillingController < Operator::BaseController
  def create
    organization = Organization.friendly.find(params[:organization_id])
    token = params[:stripeToken]
    result = UpdateOrganizationBilling.call(organization: organization, stripe_token: token)
    if result.success?
      flash[:success] = "Billing info updated."
    else
      flash[:error] = result.message
    end

    turbolinks_redirect(organization_path(organization))
  end
end


class Operator::OrganizationBillingController < Operator::BaseController
  before_action :require_authentication

  def create
    organization = Organization.friendly.find(params[:organization_id])
    # Only staff or the owner of THIS org may change its billing. Without this,
    # any authenticated member could change any org's card / out_of_band flag.
    authorize organization, :manage_billing?
    out_of_band = params[:out_of_band]
    token = params[:stripeToken]
    result = UpdateOrganizationBilling.call(organization: organization, stripe_token: token, out_of_band: out_of_band)
    if result.success?
      flash[:success] = "Billing info updated."
    else
      flash[:error] = result.message
    end

    turbo_redirect(organization_path(organization))
  end
end

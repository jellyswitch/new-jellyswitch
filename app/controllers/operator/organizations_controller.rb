class Operator::OrganizationsController < Operator::BaseController
  before_action :find_organization, except: [:index, :new, :create, :credit_card,
                                             :out_of_band, :billing, :payment_method, :members, :leases, :invoices, :ltv]

  def index
    find_organizations
    authorize @organizations

    background_image
  end

  def show
    authorize @organization
    background_image
  end

  def new
    @organization = Organization.new
    authorize @organization
    background_image
  end

  def create
    @organization = Organization.new(organization_params)
    authorize @organization

    result = CreateOrganization.call(organization: @organization, operator: current_tenant)

    if result.success?
      flash[:notice] = "Organization #{@organization.name} has been created."
      turbo_redirect(organization_path(@organization))
    else
      flash[:error] = result.message
      background_image
      render :new, status: 422
    end
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def edit
    authorize @organization
    include_stripe
    background_image
  end

  def destroy
    authorize @organization, :destroy?

    if @organization.destroy
      flash[:notice] = "#{@organization.name} deleted."
      redirect_to organizations_path
    else
      flash[:error] = "Could not delete organization."
      redirect_to organization_path(@organization)
    end
  end

  def update
    authorize @organization

    new_billing_owner = User.find_by(id: organization_params[:billing_contact_id])

    result = UpdateOrganization.call(organization: @organization, params: organization_params, operator: current_tenant, new_billing_owner: new_billing_owner)

    if result.success?
      flash[:notice] = "The organization #{@organization.reload.name} has been updated."
      turbo_redirect(organization_path(@organization))
    else
      flash[:error] = result.message
      background_image
      render :edit, status: 422
    end
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def credit_card
    find_organization(:organization_id)
    authorize @organization

    if @organization.update(out_of_band: false)
      flash[:success] = "Payment method updated."
    else
      flash[:error] = "Could not update payment method."
    end

    turbo_redirect(organization_path(@organization), action: "replace")
  end

  def out_of_band
    find_organization(:organization_id)
    authorize @organization

    if @organization.update(out_of_band: true)
      flash[:success] = "Payment method updated."
    else
      flash[:error] = "Could not update payment method."
    end

    turbo_redirect(organization_path(@organization), action: "replace")
  end

  def billing
    find_organization(:organization_id)
    authorize @organization
    include_stripe
  end

  def payment_method
    find_organization(:organization_id)
    authorize @organization
  end

  def members
    find_organization(:organization_id)
    authorize @organization
  end

  def leases
    find_organization(:organization_id)
    authorize @organization
  end

  def invoices
    find_organization(:organization_id)
    authorize @organization
  end

  def ltv
    find_organization(:organization_id)
    authorize @organization

    @months = (Time.current.year * 12 + Time.current.month) - (@organization.created_at.year * 12 + @organization.created_at.month)
  end

  private

  def organization_params
    params.require(:organization).permit(:name, :website, :owner_id, :billing_contact_id, :visible)
  end

  def find_organization(key = :id)
    @organization = Organization.for_location(current_location).friendly.find(params[key])
  end

  def find_organizations
    @organizations = Organization.for_location(current_location).visible.order(:name)
    @archived_organizations = Organization.for_location(current_location).archived.order(:name)
  end
end

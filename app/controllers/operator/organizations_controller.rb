class Operator::OrganizationsController < Operator::BaseController
  before_action :find_organization, except: [:index, :new, :create]

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

    result = CreateOrganization.call(organization: organization, operator: operator)

    if result.success?
      flash[:notice] = "Organization #{@organization.name} has been created."
      turbolinks_redirect(organization_path(@organization))
    else
      flash[:error] = result.message
      background_image
      render :new, status: 422
    end
  rescue => e
    Rollbar.error(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbolinks_redirect(referrer_or_root)
  end

  def edit
    authorize @organization
    include_stripe
    background_image
  end

  def update
    authorize @organization

    @organization.update_attributes(organization_params)

    if @organization.save
      flash[:notice] = "The organization #{@organization.name} has been updated."
      turbolinks_redirect(organization_path(@organization))
    else
      background_image
      render :edit, status: 422
    end
  rescue => e
    Rollbar.error(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbolinks_redirect(referrer_or_root)
  end

  private

  def organization_params
    params.require(:organization).permit(:name, :website, :owner_id)
  end

  def find_organization(key=:id)
    @organization = Organization.friendly.find(params[key])
  end

  def find_organizations
    @organizations = Organization.all
  end
end

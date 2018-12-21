class Operator::OrganizationsController < Operator::ApplicationController
  def index
    find_organizations
    authorize @organizations.all
    background_image
  end

  def show
    find_organization
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

    if @organization.save
      flash[:notice] = "Organization #{@organization.name} has been created."
      redirect_to organization_path(@organization)
    else
      background_image
      render :new
    end
  end

  def edit
    find_organization
    authorize @organization
    background_image
  end

  def update
    find_organization
    authorize @organization

    @organization.update_attributes(organization_params)

    if @organization.save
      flash[:notice] = "The organization #{@organization.name} has been updated."
      redirect_to organization_path(@organization)
    else
      background_image
      render :edit
    end
  end

  private

  def organization_params
    params.require(:organization).permit(:name, :website, :owner_id)
  end

  def find_organization(key=:id)
    @organization = Organization.friendly.find(params[key])
  end

  def find_organizations
    @organizations = Organization
  end
end
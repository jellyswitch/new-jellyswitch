class OrganizationsController < ApplicationController
  def index
    find_organizations
    authorize @organizations.all
  end

  def show
    find_organization
    authorize @organization
  end

  def new
    @organization = Organization.new
    authorize @organization
  end

  def create
    @organization = Organization.new(organization_params)
    authorize @organization

    if @organization.save
      flash[:notice] = "Organization #{@organization.name} has been created."
      redirect_to organization_path(@organization)
    else
      render :new
    end
  end

  def edit
    find_organization
    authorize @organization
  end

  def update
    find_organization
    authorize @organization

    @organization.update_attributes(organization_params)

    if @organization.save
      flash[:notice] = "The organization #{@organization.name} has been updated."
      redirect_to organization_path(@organization)
    else
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
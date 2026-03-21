
class Operator::OrganizationMembersController < Operator::BaseController
  before_action :require_authentication

  def create
    organization = Organization.friendly.find(params[:organization_id])

    ids = user_params[:ids]&.reject(&:blank?)
    if ids.present?
      count = User.where(id: ids).update_all(organization_id: organization.id)
    else
      count = 0
    end

    if count > 0
      flash[:success] = "Successfully added #{count} #{'member'.pluralize(count)}."
    else
      flash[:error] = "No members were added. Please select at least one member."
    end

    redirect_to organization_members_path(organization)
  end

  private

  def user_params
    params.require(:user).permit(ids: [])
  end
end

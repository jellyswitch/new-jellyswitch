
class Operator::OrganizationMembersController < Operator::BaseController
  before_action :require_authentication

  def create
    organization = Organization.friendly.find(params[:organization_id])

    users = User.where(id: user_params[:ids]).where.not(organization_id: organization.id)
    count = users.update_all(organization_id: organization.id)

    if count > 0
      flash[:success] = "Successfully added #{count} #{'member'.pluralize(count)}."
    else
      flash[:error] = "No members were added."
    end

    turbo_redirect(organization_members_path(organization))
  end

  private

  def user_params
    params.require(:user).permit(ids: [])
  end
end

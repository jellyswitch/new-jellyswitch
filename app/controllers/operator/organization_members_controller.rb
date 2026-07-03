
class Operator::OrganizationMembersController < Operator::BaseController
  before_action :require_authentication

  def create
    # `Organization` acts_as_tenant :operator, so this find is already scoped
    # to current_tenant — a foreign-operator org 404s rather than resolving.
    organization = Organization.friendly.find(params[:organization_id])

    ids = user_params[:ids]&.reject(&:blank?)
    if ids.present?
      # Scope the update to the current tenant. `User` has no acts_as_tenant,
      # so an unscoped `User.where(id: ids)` would let an operator admin POST
      # arbitrary user ids and pull users belonging to OTHER operators into
      # their organization — a cross-tenant write. `current_tenant.users`
      # mirrors the tenant scoping the add-member form already applies.
      count = current_tenant.users.where(id: ids).update_all(organization_id: organization.id)
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

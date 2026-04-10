class Api::V1::OrganizationsController < Api::V1::BaseController
  def show
    org = current_api_user.organization
    return render json: { organization: nil } unless org

    members = org.users.map { |u|
      { id: u.id, name: u.name, email: u.email, role: u.role }
    }

    render json: {
      id: org.id,
      name: org.name,
      members: members,
      member_count: org.users.count,
    }
  end
end

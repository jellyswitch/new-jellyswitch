class Api::V1::Admin::SearchController < Api::V1::Admin::BaseController
  def index
    q = "%#{params[:q]}%"
    return render json: { members: [], organizations: [], rooms: [], doors: [] } if params[:q].blank?

    members = current_tenant.users
      .where("users.name ILIKE ? OR users.email ILIKE ?", q, q)
      .limit(10)
      .map { |u| { id: u.id, name: u.name, email: u.email, type: "member" } }

    organizations = Organization.where(operator: current_tenant)
      .where("organizations.name ILIKE ?", q)
      .limit(10)
      .map { |o| { id: o.id, name: o.name, type: "organization" } }

    rooms = Room.where(operator: current_tenant)
      .where("rooms.name ILIKE ?", q)
      .limit(10)
      .map { |r| { id: r.id, name: r.name, type: "room" } }

    doors = Door.where(operator: current_tenant)
      .where("doors.name ILIKE ?", q)
      .limit(10)
      .map { |d| { id: d.id, name: d.name, type: "door" } }

    render json: {
      members: members,
      organizations: organizations,
      rooms: rooms,
      doors: doors,
    }
  end
end

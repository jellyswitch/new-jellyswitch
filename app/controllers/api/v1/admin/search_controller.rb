class Api::V1::Admin::SearchController < Api::V1::Admin::BaseController
  def index
    q = "%#{params[:q]}%"
    return render json: { members: [], organizations: [], rooms: [], doors: [], events: [], plans: [], invoices: [] } if params[:q].blank?

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

    events = Event.where(location: current_location)
      .where("events.title ILIKE ?", q)
      .limit(10)
      .map { |e| { id: e.id, name: e.title, date: e.starts_at&.strftime("%B %e, %Y"), type: "event" } }

    plans = Plan.where(operator: current_tenant)
      .where("plans.name ILIKE ?", q)
      .limit(10)
      .map { |p| { id: p.id, name: p.name, amount: p.amount_in_cents, type: "plan" } }

    invoices = Invoice.where(operator: current_tenant)
      .where("invoices.description ILIKE ?", q)
      .limit(10)
      .map { |i| { id: i.id, name: i.try(:description) || "Invoice ##{i.id}", amount: i.amount_due, status: i.status, type: "invoice" } }

    render json: {
      members: members,
      organizations: organizations,
      rooms: rooms,
      doors: doors,
      events: events,
      plans: plans,
      invoices: invoices,
    }
  end
end

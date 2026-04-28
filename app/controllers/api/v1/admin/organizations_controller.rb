class Api::V1::Admin::OrganizationsController < Api::V1::Admin::BaseController
  def index
    orgs = Organization.where(operator: current_tenant).order(:name)

    render json: orgs.map { |org|
      {
        id: org.id,
        name: org.name,
        member_count: org.users.count,
        active_lease: org.has_active_lease?,
      }
    }
  end

  def show
    org = Organization.find(params[:id])

    members = org.users.map { |u|
      { id: u.id, name: u.name, email: u.email, role: u.role }
    }

    leases = org.office_leases.map { |l|
      {
        id: l.id,
        office: l.office&.name,
        start_date: l.start_date,
        end_date: l.end_date,
      }
    }

    invoices = org.invoices.order(date: :desc).limit(20).map { |i|
      {
        id: i.id,
        number: i.number,
        amount_due: i.amount_due,
        amount_paid: i.amount_paid,
        status: i.status,
        date: i.date,
      }
    }

    render json: {
      id: org.id,
      name: org.name,
      member_count: org.users.count,
      members: members,
      leases: leases,
      invoices: invoices,
      ltv: org.invoices.sum(:amount_paid),
    }
  end

  def create
    org = Organization.new(name: params[:name], operator: current_tenant)

    if org.save
      render json: { id: org.id, name: org.name }, status: :created
    else
      render_error(org.errors.full_messages.join(', '))
    end
  end

  def update
    org = Organization.find(params[:id])

    if org.update(organization_params)
      render json: { id: org.id, name: org.name }
    else
      render_error(org.errors.full_messages.join(', '))
    end
  end

  private

  def organization_params
    params.permit(:name, :website, :visible)
  end
end

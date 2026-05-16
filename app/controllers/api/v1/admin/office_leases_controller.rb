class Api::V1::Admin::OfficeLeasesController < Api::V1::Admin::BaseController
  def index
    leases = OfficeLease.where(operator: current_tenant).order(created_at: :desc)

    render json: leases.map { |l| lease_json(l) }
  end

  def create
    lease = OfficeLease.new(lease_params)
    lease.operator = current_tenant

    if lease.save
      render json: lease_json(lease), status: :created
    else
      render_error(lease.errors.full_messages.join(', '))
    end
  end

  def show
    lease = OfficeLease.find(params[:id])
    render json: lease_json(lease)
  rescue ActiveRecord::RecordNotFound
    render_error('Lease not found', status: :not_found)
  end

  def update_price
    lease = OfficeLease.find(params[:id])
    new_amount = params[:amount_in_cents].to_i

    if lease.subscription&.plan
      lease.subscription.plan.update(amount_in_cents: new_amount)
      render json: { success: true, lease: lease_json(lease.reload) }
    else
      render_error('No subscription plan found for this lease')
    end
  rescue ActiveRecord::RecordNotFound
    render_error('Lease not found', status: :not_found)
  end

  def terminate
    lease = OfficeLease.find(params[:id])
    lease.update(end_date: Date.current)
    if lease.subscription
      lease.subscription.update(active: false)
    end
    render json: { success: true, message: 'Lease terminated.' }
  rescue ActiveRecord::RecordNotFound
    render_error('Lease not found', status: :not_found)
  end

  def renewals
    leases = OfficeLease.where(operator: current_tenant)
      .where("end_date >= ? AND end_date <= ?", Date.current, Date.current + 60.days)
      .order(:end_date)

    render json: leases.map { |l| lease_json(l) }
  end

  private

  def lease_params
    params.require(:office_lease).permit(:office_id, :organization_id, :user_id, :start_date, :end_date, :location_id, :subscription_id)
  end

  def lease_json(l)
    {
      id: l.id,
      office_name: l.office&.name,
      lessee_name: l.leasee_name,
      start_date: l.start_date,
      end_date: l.end_date,
      monthly_rate: l.subscription&.plan&.amount_in_cents,
      status: lease_status(l),
    }
  end

  def lease_status(l)
    if l.active?
      'active'
    elsif l.end_date < Date.current
      'expired'
    else
      'upcoming'
    end
  end
end

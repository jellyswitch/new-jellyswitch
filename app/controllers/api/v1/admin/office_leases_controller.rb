class Api::V1::Admin::OfficeLeasesController < Api::V1::Admin::BaseController
  def index
    leases = OfficeLease.where(operator: current_tenant).order(created_at: :desc)

    render json: leases.map { |l| lease_json(l) }
  end

  # Same pipeline as the web "New Office Lease" form (plan + lease + Stripe
  # subscription + deposit + emails). The old version did a bare
  # OfficeLease.new(...).save with no subscription, so it could never succeed.
  def create
    lease = current_location.office_leases.build(lease_params)
    lease.operator = current_tenant
    lease.start_date ||= Date.current
    lease.end_date ||= lease.start_date + 1.year
    # Bill from the lease start, or today if the lease already started.
    lease.initial_invoice_date ||= [lease.start_date, Date.current].max
    lease.deposit_amount_in_cents ||= 0

    lease.build_subscription
    lease.subscription.build_plan(
      name: "Office Lease Plan",
      plan_type: "lease",
      interval: params.dig(:office_lease, :interval).presence || "monthly",
      amount_in_cents: params.dig(:office_lease, :amount_in_cents).to_i,
      location_id: current_location.id,
    )

    result = Billing::Leasing::CreateOfficeLease.call(
      office_lease: lease,
      operator: current_tenant,
      plan: lease.subscription.plan,
      location: current_location,
    )

    if result.success?
      render json: lease_json(result.office_lease), status: :created
    else
      render_error(result.message.presence || "Could not create lease")
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
    params.require(:office_lease).permit(:office_id, :organization_id, :user_id, :start_date, :end_date, :initial_invoice_date, :deposit_amount_in_cents)
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

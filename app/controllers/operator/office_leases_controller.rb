class Operator::OfficeLeasesController < Operator::BaseController
  before_action :find_office_lease, only: [:show]
  before_action :background_image, except: [:create, :update]

  def index
    @office_leases = OfficeLease.order(created_at: :desc)
    authorize @office_leases
  end

  def show
    authorize @office_lease
  end

  def new
    @office_lease = OfficeLease.new
    @office_lease.build_subscription
    @office_lease.subscription.build_plan
    find_organizations
    find_offices
    find_plans
    authorize @office_lease
  end

  def create
    @office_lease = current_tenant.office_leases.build(office_lease_params)

    authorize @office_lease

    result = Billing::Leasing::CreateOfficeLease.call(
      office_lease: @office_lease,
      operator: current_tenant
    )

    if result.success?
      flash[:notice] = "Office lease created."
      turbolinks_redirect(office_leases_path)
    else
      flash[:error] = result.message
      find_organizations
      find_offices
      find_plans
      render :new, status: 422
    end
  end

  private

  def find_office_lease(key=:id)
    @office_lease = OfficeLease.find(params[key])
  end

  def office_lease_params
    params.require(:office_lease).permit(
      :organization_id,
      :office_id,
      :start_date,
      :lease_agreement,
      :end_date,
      :initial_invoice_date,
      subscription_attributes: [
        plan_attributes: [
          :name,
          :plan_type,
          :visible,
          :available,
          :interval,
          :amount_in_cents
          ]
        ]
    )
  end

  def find_organizations
    @organizations = Organization.eligible_for_lease.all
  end

  def find_offices
    @offices = Office.available_for_lease
  end

  def find_plans
    @plans = Plan.lease
  end
end

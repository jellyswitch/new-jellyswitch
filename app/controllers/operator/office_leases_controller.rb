class Operator::OfficeLeasesController < Operator::BaseController
  before_action :find_office_lease, only: [:show]
  before_action :background_image, except: [:create, :update]

  def index
    @office_leases = current_location.office_leases.order(created_at: :desc)
    authorize @office_leases
  end

  def show
    authorize @office_lease
  end

  def new
    @office_lease = initialize_office_lease
    find_organizations
    find_users
    find_offices
    find_plans

    # Pre-fill user if coming from "Upgrade to Office" on user profile
    if params[:user_id].present?
      @office_lease.user_id = params[:user_id]
    end

    authorize @office_lease
  end

  def renewal
    @current_lease = OfficeLease.find(params[:office_lease_id])
    authorize @current_lease, :renewal?

    @office_lease = Billing::Leasing::InitializeRenewalOfficeLease.call(active_lease: @current_lease).renewal_lease

    find_plans
    @organizations = @office_lease.organization.present? ? [@office_lease.organization] : []
    @users = @office_lease.user.present? ? [@office_lease.user] : []
    @offices = [@office_lease.office]
  end

  def edit_price
    @office_lease = OfficeLease.find(params[:office_lease_id])
    @plan_interval = @office_lease.subscription.plan.interval
    @display_interval = @office_lease.subscription.plan.display_interval

    authorize @office_lease, :edit_price?

    @next_billing_cycle = Time.at(@office_lease.current_period_end)
  end

  def update_price
    @office_lease = OfficeLease.find(params[:office_lease_id])
    authorize @office_lease, :update_price?

    result = Billing::Leasing::UpdateLeasePrice.call(
      office_lease: @office_lease,
      new_price_in_cents: params[:office_lease][:new_price].to_i,
      operator: current_tenant,
    )

    if result.success?
      flash[:notice] = "Lease price updated successfully."
      turbo_redirect(office_lease_path(@office_lease))
    else
      flash[:error] = result.message
      turbo_redirect(office_lease_edit_price_path(@office_lease))
    end
  end

  def create
    @office_lease = current_location.office_leases.build(office_lease_params)
    @office_lease.subscription.plan.location_id = current_location.id

    authorize @office_lease

    result = Billing::Leasing::CreateOfficeLease.call(
      office_lease: @office_lease,
      operator: current_tenant,
      plan: @office_lease.subscription.plan,
      location: current_location,
      )

    if result.success?
      flash[:notice] = "Office lease created."
      session[:should_track_pixels] = true
      turbo_redirect(office_lease_path(result.office_lease))
    else
      flash[:error] = result.message
      find_organizations
      find_users
      find_offices
      find_plans
      turbo_redirect(new_office_lease_path, action: "replace")
    end
  end

  def destroy
    find_office_lease
    authorize @office_lease

    result = Billing::Leasing::SetOfficeLeaseForTermination.call(
      office_lease: @office_lease,
      subscription: @office_lease.subscription,
    )

    if result.success?
      flash[:success] = "This lease is scheduled for termination. Any outstanding invoices may still need to be addressed."
    else
      flash[:error] = result.message
    end
    turbo_redirect(office_lease_path(@office_lease), action: "replace")
  end

  def convert_to_organization
    find_office_lease
    authorize @office_lease

    user = @office_lease.user
    unless @office_lease.individual_lease?
      flash[:error] = "This lease is already linked to an organization."
      turbo_redirect(office_lease_path(@office_lease))
      return
    end

    organization = Organization.new(
      name: "#{user.name}'s Office",
      owner: user,
      billing_contact: user,
      operator: current_tenant,
      location: current_location
    )

    if organization.save
      # Create Stripe customer for the org using the user's email
      Billing::Payment::CreateStripeCustomer.call(billable: organization, operator: current_tenant, location: current_location)

      # Move the lease from user to organization
      user.update(organization: organization)
      @office_lease.update(organization: organization, user_id: nil)

      flash[:success] = "Organization '#{organization.name}' created. You can now add members."
      turbo_redirect(organization_path(organization))
    else
      flash[:error] = "Could not create organization: #{organization.errors.full_messages.join(', ')}"
      turbo_redirect(office_lease_path(@office_lease))
    end
  end

  def destroy_office_lease_now
    find_office_lease
    authorize @office_lease

    result = Billing::Leasing::TerminateOfficeLease.call(
      office_lease: @office_lease,
      subscription: @office_lease.subscription,
    )

    if result.success?
      flash[:success] = "This lease has been terminated. Any outstanding invoices may still need to be addressed."
    else
      flash[:error] = result.message
    end
    turbo_redirect(office_lease_path(@office_lease), action: "replace")
  end

  private

  def find_office_lease(key = :id)
    @office_lease = OfficeLease.find(params[key])
  end

  def office_lease_params
    params.require(:office_lease).permit(
      :organization_id,
      :user_id,
      :office_id,
      :start_date,
      :lease_agreement,
      :end_date,
      :initial_invoice_date,
      :deposit_amount_in_cents,
      :auto_renew,
      :renewal_notice_days,
      :escalation_type,
      :escalation_value,
      :cpi_index_series_id,
      subscription_attributes: [
        plan_attributes: [
          :name,
          :plan_type,
          :visible,
          :available,
          :interval,
          :amount_in_cents,
        ],
      ],
    )
  end

  def find_organizations
    @organizations = current_location.organizations.visible.where(
      "stripe_customer_id IS NOT NULL AND stripe_customer_id != '' OR out_of_band = ?", true
    )
  end

  def find_users
    @users = User.for_space(current_tenant).originally_at_location(current_location).non_superadmins.approved.visible.order(:name)
  end

  def find_offices
    @offices = Office.available_for_lease
  end

  def find_plans
    @plans = Plan.lease
  end

  def initialize_office_lease
    office_lease = OfficeLease.new
    office_lease.build_subscription
    office_lease.subscription.build_plan
    office_lease
  end
end

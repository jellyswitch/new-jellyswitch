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

    period_end = @office_lease.current_period_end
    @next_billing_cycle = period_end ? Time.at(period_end) : @office_lease.end_date
  end

  def update_price
    @office_lease = OfficeLease.find(params[:office_lease_id])
    authorize @office_lease, :update_price?

    result = Billing::Leasing::UpdateLeasePrice.call(
      office_lease: @office_lease,
      new_price_in_cents: (params[:office_lease][:new_price].to_f * 100).round,
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
    convert_money_fields_to_cents
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
    find_office_lease(:office_lease_id)
    authorize @office_lease

    user = @office_lease.user
    unless @office_lease.individual_lease?
      flash[:error] = "This lease is already linked to an organization."
      redirect_to office_lease_path(@office_lease)
      return
    end

    ActiveRecord::Base.transaction do
      organization = Organization.create!(
        name: "#{user.name}'s Office",
        owner: user,
        billing_contact: user,
        operator: current_tenant,
        location: current_location
      )

      Billing::Payment::CreateStripeCustomer.call(billable: organization, operator: current_tenant, location: current_location)

      user.update!(organization: organization)
      @office_lease.update!(organization: organization, user_id: nil)

      flash[:success] = "Organization '#{organization.name}' created. You can now add members."
      redirect_to organization_path(organization) and return
    end
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "Error converting to organization: #{e.message}"
    redirect_to offices_path
  end

  def destroy_office_lease_now
    find_office_lease
    authorize @office_lease

    result = Billing::Leasing::TerminateOfficeLease.call(
      office_lease: @office_lease,
      subscription: @office_lease.subscription,
      prorate: false,
    )

    if result.success?
      flash[:success] = "This lease has been terminated. Any outstanding invoices may still need to be addressed."
    else
      flash[:error] = result.message
    end
    turbo_redirect(office_lease_path(@office_lease), action: "replace")
  end

  # Recovery for a deposit that wasn't auto-invoiced at lease creation (silent
  # ChargeDeposit failure, or a deposit added later). Idempotent — ChargeDeposit
  # no-ops if deposit_invoiced_at is already set. See the lease show page.
  def charge_deposit
    find_office_lease(:office_lease_id)
    authorize @office_lease

    Billing::Leasing::ChargeDeposit.call(office_lease: @office_lease, operator: current_tenant)

    if @office_lease.reload.deposit_invoiced_at.present?
      flash[:success] = "Deposit invoice generated."
    else
      flash[:error] = "Couldn't generate the deposit invoice — check the member's billing setup and try again, or mark it as already invoiced."
    end
    turbo_redirect(office_lease_path(@office_lease))
  end

  # For deposits collected out-of-band (cash, a manual Stripe invoice, waived):
  # clear the "deposit not invoiced" flag WITHOUT charging.
  def mark_deposit_invoiced
    find_office_lease(:office_lease_id)
    authorize @office_lease

    @office_lease.update!(deposit_invoiced_at: Time.current)
    flash[:success] = "Deposit marked as already invoiced."
    turbo_redirect(office_lease_path(@office_lease))
  end

  private

  # The lease form collects money in dollars (e.g. "579" or "579.00"). Convert
  # to integer cents server-side rather than relying on client JS — a dropped
  # conversion stores the amount 100x too small (e.g. $5.79 instead of $579).
  # Mirrors the server-side conversion in #update_price.
  def convert_money_fields_to_cents
    lease = params[:office_lease]
    return if lease.blank?

    if lease[:deposit_amount_in_cents].present?
      lease[:deposit_amount_in_cents] = (lease[:deposit_amount_in_cents].to_f * 100).round
    end

    plan = lease.dig(:subscription_attributes, :plan_attributes)
    if plan.present? && plan[:amount_in_cents].present?
      plan[:amount_in_cents] = (plan[:amount_in_cents].to_f * 100).round
    end
  end

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

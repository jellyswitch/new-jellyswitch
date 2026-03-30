class Operator::LeaseRenewalRequestsController < Operator::BaseController
  before_action :require_authentication
  before_action :background_image
  before_action :find_request, except: [:index]

  def index
    authorize LeaseRenewalRequest, :index?
    @pending_requests = current_location.lease_renewal_requests.pending.includes(office_lease: [:office, :user, :organization]).order(created_at: :desc)
    @resolved_requests = current_location.lease_renewal_requests.resolved.includes(office_lease: [:office, :user, :organization]).order(updated_at: :desc).limit(20)
  end

  def show
    authorize @request
  end

  def accept
    authorize @request
    @request.accept!(notes: params[:notes])

    # Create the renewal lease
    create_renewal_lease(@request)

    flash[:success] = "Renewal accepted. Your new lease has been created."
    turbo_redirect(lease_renewal_request_path(@request))
  end

  def request_modification
    authorize @request
    @request.request_modification!(notes: params[:notes])

    flash[:success] = "Your modification request has been sent to the admin."
    turbo_redirect(lease_renewal_request_path(@request))
  end

  def admin_review
    authorize @request
  end

  def admin_approve
    authorize @request
    price_override = params[:price_override].present? ? (params[:price_override].to_f * 100).to_i : nil
    @request.admin_approve!(notes: params[:notes], price_override: price_override)

    create_renewal_lease(@request)

    flash[:success] = "Renewal approved and new lease created."
    turbo_redirect(lease_renewal_request_path(@request))
  end

  def admin_decline
    authorize @request
    @request.admin_decline!(notes: params[:notes])

    flash[:success] = "Renewal declined."
    turbo_redirect(lease_renewal_request_path(@request))
  end

  def admin_force_approve
    authorize @request
    price_override = params[:price_override].present? ? (params[:price_override].to_f * 100).to_i : nil
    @request.admin_approve!(notes: params[:notes], price_override: price_override)

    create_renewal_lease(@request)

    flash[:success] = "Renewal force-approved and new lease created."
    turbo_redirect(lease_renewal_request_path(@request))
  end

  private

  def find_request
    @request = LeaseRenewalRequest.find(params[:id])
  end

  def create_renewal_lease(request)
    lease = request.office_lease
    renewal = Billing::Leasing::InitializeRenewalOfficeLease.call(active_lease: lease).renewal_lease
    renewal.subscription.plan.amount_in_cents = request.proposed_price_in_cents
    renewal.subscription.plan.location_id = lease.location_id

    # Copy auto-renewal settings to the new lease
    renewal.auto_renew = lease.auto_renew
    renewal.renewal_notice_days = lease.renewal_notice_days
    renewal.escalation_type = lease.escalation_type
    renewal.escalation_value = lease.escalation_value
    renewal.cpi_index_series_id = lease.cpi_index_series_id

    result = Billing::Leasing::CreateOfficeLease.call(
      office_lease: renewal,
      operator: lease.operator,
      plan: renewal.subscription.plan,
      location: lease.location
    )

    unless result.success?
      flash[:error] = "Renewal lease creation failed: #{result.message}"
    end
  end
end

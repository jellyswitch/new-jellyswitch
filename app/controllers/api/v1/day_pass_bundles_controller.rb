class Api::V1::DayPassBundlesController < Api::V1::BaseController
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  def index
    bundles = current_api_user.day_pass_bundles.active.order(:id)
    render json: bundles.map { |b|
      {
        id: b.id,
        day_pass_type_name: b.day_pass_type.name,
        location_id: b.location_id,
        passes_remaining: b.passes_remaining,
        expires_at: b.expires_at,
      }
    }
  end

  def check_in_guest
    bundle = current_api_user.day_pass_bundles.find(params[:id])
    result = Billing::DayPassBundles::CheckInGuest.call(
      bundle: bundle,
      performed_by: current_api_user,
      guest_name: params[:guest_name],
    )
    if result.success?
      render json: { id: bundle.id, passes_remaining: bundle.reload.passes_remaining }
    else
      render_error(result.message)
    end
  end

  private

  def render_not_found
    render json: { error: "Not found" }, status: :not_found
  end
end

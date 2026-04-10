class Api::V1::CheckinsController < Api::V1::BaseController
  def current
    checkin = current_api_user.checkins
      .where(operator: current_tenant, location: current_location)
      .where(checked_out_at: nil)
      .order(created_at: :desc)
      .first

    if checkin
      render json: {
        id: checkin.id,
        checked_in_at: checkin.created_at.iso8601,
        duration_minutes: ((Time.current - checkin.created_at) / 60).round,
      }
    else
      render json: { checkin: nil }
    end
  end

  def create
    checkin = Checkin.new(
      user: current_api_user,
      operator: current_tenant,
      location: current_location,
    )

    if checkin.save
      render json: {
        id: checkin.id,
        checked_in_at: checkin.created_at.iso8601,
      }, status: :created
    else
      render_error(checkin.errors.full_messages.first)
    end
  end

  def destroy
    checkin = current_api_user.checkins.find(params[:id])
    checkin.update(checked_out_at: Time.current)
    render json: { success: true }
  rescue ActiveRecord::RecordNotFound
    render_error('Checkin not found', status: :not_found)
  end
end

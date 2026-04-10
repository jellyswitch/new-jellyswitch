class Api::V1::CheckinsController < Api::V1::BaseController
  def current
    checkin = current_api_user.checkins
      .where(location: current_location)
      .where(datetime_out: nil)
      .order(datetime_in: :desc)
      .first

    if checkin
      render json: {
        id: checkin.id,
        checked_in_at: checkin.datetime_in.iso8601,
        duration_minutes: ((Time.current - checkin.datetime_in) / 60).round,
      }
    else
      render json: { checkin: nil }
    end
  end

  def create
    checkin = Checkin.new(
      user: current_api_user,
      location: current_location,
      datetime_in: Time.current,
    )

    if checkin.save
      render json: {
        id: checkin.id,
        checked_in_at: checkin.datetime_in.iso8601,
      }, status: :created
    else
      render_error(checkin.errors.full_messages.first)
    end
  end

  def destroy
    checkin = current_api_user.checkins.find(params[:id])
    checkin.update(datetime_out: Time.current)
    render json: { success: true }
  rescue ActiveRecord::RecordNotFound
    render_error('Checkin not found', status: :not_found)
  end
end

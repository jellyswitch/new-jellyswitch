class Api::V1::Admin::CheckinsController < Api::V1::Admin::BaseController
  def index
    checkins = Checkin.where(location: current_location)
      .where(datetime_in: Date.current.all_day)
      .order(datetime_in: :desc)

    render json: checkins.map { |c|
      {
        id: c.id,
        user_name: c.user&.name,
        checked_in_at: c.datetime_in.iso8601,
        checked_out_at: c.datetime_out&.iso8601,
        duration_minutes: c.datetime_out ? c.minutes : ((Time.current - c.datetime_in) / 60).round,
      }
    }
  end

  def create
    user = User.find(params[:user_id])
    checkin = Checkin.new(
      user: user,
      datetime_in: Time.current,
      location: current_location,
    )

    if checkin.save
      render json: {
        id: checkin.id,
        user_name: user.name,
        checked_in_at: checkin.datetime_in.iso8601,
      }, status: :created
    else
      render_error(checkin.errors.full_messages.join(', '))
    end
  end
end

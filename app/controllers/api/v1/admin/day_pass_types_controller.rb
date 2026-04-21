class Api::V1::Admin::DayPassTypesController < Api::V1::Admin::BaseController
  def index
    types = DayPassType.where(operator: current_tenant).order(:amount_in_cents)

    render json: types.map { |t| type_json(t) }
  end

  def create
    type = DayPassType.new(type_params)
    type.operator = current_tenant
    type.location = current_location

    if type.save
      render json: type_json(type), status: :created
    else
      render_error(type.errors.full_messages.join(', '))
    end
  end

  def update
    type = DayPassType.find(params[:id])

    DayPassType.transaction do
      if params.dig(:day_pass_type, :default_for_room_booking).to_s == 'true'
        # Only one default per operator/location pair.
        DayPassType
          .where(operator_id: type.operator_id, location_id: type.location_id)
          .where.not(id: type.id)
          .update_all(default_for_room_booking: false)
      end

      if type.update(type_params)
        render json: type_json(type)
      else
        render_error(type.errors.full_messages.join(', '))
        raise ActiveRecord::Rollback
      end
    end
  end

  private

  def type_params
    params.require(:day_pass_type).permit(
      :name, :amount_in_cents, :available, :visible, :description,
      :included_meeting_room_minutes, :overage_rate_in_cents,
      :default_for_room_booking,
    )
  end

  def type_json(t)
    {
      id: t.id,
      name: t.name,
      price_in_cents: t.amount_in_cents,
      available: t.available,
      description: t.description.to_s,
      included_meeting_room_minutes: t.try(:included_meeting_room_minutes),
      overage_rate_in_cents: t.try(:overage_rate_in_cents),
      default_for_room_booking: t.try(:default_for_room_booking),
    }
  end
end

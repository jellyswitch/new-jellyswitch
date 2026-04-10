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

    if type.update(type_params)
      render json: type_json(type)
    else
      render_error(type.errors.full_messages.join(', '))
    end
  end

  private

  def type_params
    params.require(:day_pass_type).permit(:name, :amount_in_cents, :available, :visible, :description)
  end

  def type_json(t)
    {
      id: t.id,
      name: t.name,
      price_in_cents: t.amount_in_cents,
      available: t.available,
      description: t.description.to_s,
      included_meeting_room_minutes: t.try(:included_meeting_room_minutes),
    }
  end
end

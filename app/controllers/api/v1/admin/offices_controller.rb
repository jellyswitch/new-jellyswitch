class Api::V1::Admin::OfficesController < Api::V1::Admin::BaseController
  def index
    offices = Office.where(operator: current_tenant)

    render json: offices.map { |o| office_json(o) }
  end

  def create
    office = Office.new(office_params)
    office.operator = current_tenant
    office.location = current_location

    if office.save
      render json: office_json(office), status: :created
    else
      render_error(office.errors.full_messages.join(', '))
    end
  end

  def update
    office = Office.find(params[:id])

    if office.update(office_params)
      render json: office_json(office)
    else
      render_error(office.errors.full_messages.join(', '))
    end
  end

  def destroy
    office = Office.find(params[:id])
    office.destroy
    render json: { success: true }
  end

  private

  def office_params
    params.require(:office).permit(:name, :square_footage, :capacity, :visible, :description)
  end

  def office_json(o)
    {
      id: o.id,
      name: o.name,
      square_footage: o.square_footage,
      occupied: o.has_active_lease?,
      monthly_rate: o.active_lease&.subscription&.plan&.amount_in_cents,
      archived: !o.visible,
    }
  end
end

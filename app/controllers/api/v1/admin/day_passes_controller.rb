class Api::V1::Admin::DayPassesController < Api::V1::Admin::BaseController
  def index
    day_passes = DayPass.where(operator: current_tenant)
      .order(created_at: :desc)
      .limit(30)

    render json: day_passes.map { |dp| day_pass_json(dp) }
  end

  private

  def day_pass_json(dp)
    {
      id: dp.id,
      user_name: dp.user&.name,
      date: dp.day,
      type_name: dp.day_pass_type&.name,
      paid: dp.stripe_charge_id.present? || dp.invoice_id.present?,
      complimentary: dp.complimentary,
    }
  end
end

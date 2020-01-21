class Operator::ChildcareSlotsController < Operator::BaseController
  before_action :background_image

  def index
    find_childcare_slots
  end

  private

  def find_childcare_slots
    current_location.childcare_slots.visible.order(:week_day)
  end

end
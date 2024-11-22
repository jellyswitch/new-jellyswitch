class Operator::ChildcareController < Operator::BaseController
  before_action :background_image

  def index
    if current_user.admin_of_location?(current_location)
      @upcoming_reservations = current_location.childcare_reservations.upcoming.all
    else
      @upcoming_reservations = current_user.childcare_reservations.upcoming.all
    end
  end
end
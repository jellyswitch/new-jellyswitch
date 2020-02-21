class Operator::LeadsController < Operator::BaseController
  include LeadsHelper
  before_action :background_image
  
  def index
    find_leads
    authorize @leads
  end

  def show
    find_lead
    authorize @lead
  end
end
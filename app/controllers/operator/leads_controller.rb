class Operator::LeadsController < Operator::BaseController
  include LeadsHelper
  before_action :background_image
  
  def index
    find_leads
  end

  def show
    find_lead
  end
end
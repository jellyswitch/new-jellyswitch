class Operator::LeadsController < Operator::BaseController
  before_action :background_image
  
  def index
    find_leads
  end

  private

  def find_leads
    @leads = current_tenant.leads.order("created_at DESC").all
  end
end
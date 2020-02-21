class Operator::LeadsController < Operator::BaseController
  before_action :background_image
  
  def index
    find_leads
  end

  def show
    find_lead
  end

  private

  def find_leads
    @leads = current_tenant.leads.order("created_at DESC").all
  end

  def find_lead(key=:id)
    @lead = current_tenant.leads.find(params[key])
  end
end
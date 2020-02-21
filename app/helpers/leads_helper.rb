module LeadsHelper
  private

  def find_leads
    @leads = current_tenant.leads.order("created_at DESC").all
  end

  def find_lead(key=:id)
    @lead = current_tenant.leads.find(params[key])
  end

  def lead_note_params
    params.require(:lead_note).permit(:user_id, :lead_id, :content)
  end
end
class Operator::LeadNotesController < Operator::BaseController
  include LeadsHelper
  before_action :require_authentication

  def create
    @lead = find_lead(:lead_id)
    @lead_note = @lead.lead_notes.new(lead_note_params)
    if !@lead_note.save
      flash[:error] = "Something went wrong."
    end
    turbo_redirect(lead_path(@lead), action: "replace")
  end
end
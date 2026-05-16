class Api::V1::Admin::LeadNotesController < Api::V1::Admin::BaseController
  def create
    lead = Lead.find(params[:lead_id])
    note = lead.lead_notes.build(user: current_api_user)
    note.content = params[:body]

    if note.save
      render json: {
        id: note.id,
        body: note.content&.to_plain_text,
        author: current_api_user.name,
        created_at: note.created_at.iso8601,
      }, status: :created
    else
      render_error(note.errors.full_messages.join(', '))
    end
  end
end

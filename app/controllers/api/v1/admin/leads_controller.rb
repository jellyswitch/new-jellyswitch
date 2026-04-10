class Api::V1::Admin::LeadsController < Api::V1::Admin::BaseController
  def index
    leads = Lead.where(operator: current_tenant).order(created_at: :desc).limit(30)

    render json: leads.map { |l|
      {
        id: l.id,
        name: l.user&.name,
        email: l.user&.email,
        phone: l.user&.phone,
        status: l.status,
        created_at: l.created_at.iso8601,
      }
    }
  end

  def show
    lead = Lead.find(params[:id])

    notes = lead.lead_notes.order(created_at: :desc).map { |n|
      {
        id: n.id,
        body: n.content&.to_plain_text,
        author: n.user&.name,
        created_at: n.created_at.iso8601,
      }
    }

    render json: {
      id: lead.id,
      name: lead.user&.name,
      email: lead.user&.email,
      phone: lead.user&.phone,
      status: lead.status,
      source: lead.source,
      created_at: lead.created_at.iso8601,
      notes: notes,
    }
  end

  def update
    lead = Lead.find(params[:id])

    if lead.update(lead_params)
      render json: { id: lead.id, status: lead.status }
    else
      render_error(lead.errors.full_messages.join(', '))
    end
  end

  private

  def lead_params
    params.permit(:status, :source)
  end
end

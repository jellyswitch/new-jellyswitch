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

  def create
    user = User.new(
      name: params[:name],
      email: params[:email],
      phone: params[:phone],
      password: SecureRandom.hex(8),
      operator: current_tenant,
      original_location: current_location,
      approved: false,
    )

    if user.save
      lead = Lead.create(
        user: user,
        operator: current_tenant,
        source: params[:source] || 'manual',
        status: 'new',
      )
      render json: lead_json(lead), status: :created
    else
      render_error(user.errors.full_messages.join(', '))
    end
  end

  def update
    lead = Lead.find(params[:id])

    if lead.update(lead_params)
      render json: lead_json(lead)
    else
      render_error(lead.errors.full_messages.join(', '))
    end
  end

  def convert_to_member
    lead = Lead.find(params[:id])
    user = lead.user
    return render_error('No user associated with this lead') unless user

    user.update(approved: true)
    lead.update(status: 'converted')

    render json: { success: true, message: "#{user.name} is now an approved member." }
  rescue ActiveRecord::RecordNotFound
    render_error('Lead not found', status: :not_found)
  end

  def destroy
    lead = Lead.find(params[:id])
    lead.destroy
    render json: { success: true }
  rescue ActiveRecord::RecordNotFound
    render_error('Lead not found', status: :not_found)
  end

  private

  def lead_params
    params.permit(:status, :source)
  end

  def lead_json(lead)
    {
      id: lead.id,
      name: lead.user&.name,
      email: lead.user&.email,
      phone: lead.user&.phone,
      status: lead.status,
      source: lead.source,
      created_at: lead.created_at.iso8601,
    }
  end
end

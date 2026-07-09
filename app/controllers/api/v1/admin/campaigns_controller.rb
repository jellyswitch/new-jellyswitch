class Api::V1::Admin::CampaignsController < Api::V1::Admin::BaseController
  def index
    campaigns = Campaign.where(operator: current_tenant).order(created_at: :desc)

    render json: campaigns.map { |c|
      {
        id: c.id,
        name: c.name,
        subject: c.campaign_steps.first&.subject,
        status: c.status,
        recipient_count: c.recipient_count,
        sent_at: c.sent_at&.iso8601,
        created_at: c.created_at.iso8601,
      }
    }
  end

  def show
    campaign = current_tenant.campaigns.find(params[:id])
    render json: campaign_detail_json(campaign)
  end

  def create
    campaign = Campaign.new(campaign_params)
    campaign.operator = current_tenant

    if campaign.save
      render json: { id: campaign.id, name: campaign.name }, status: :created
    else
      render_error(campaign.errors.full_messages.join(', '))
    end
  end

  def update
    campaign = current_tenant.campaigns.find(params[:id])

    if campaign.update(campaign_params)
      render json: { id: campaign.id, name: campaign.name }
    else
      render_error(campaign.errors.full_messages.join(', '))
    end
  end

  def send_campaign
    campaign = current_tenant.campaigns.find(params[:id])
    campaign.update!(status: 'active', sent_at: Time.current)
    SendCampaignJob.perform_later(campaign.id, current_location.id)

    render json: { success: true, message: "Campaign is being sent" }
  end

  def pause
    campaign = current_tenant.campaigns.find(params[:id])
    campaign.update!(status: 'paused')

    render json: { success: true, status: 'paused' }
  end

  def resume
    campaign = current_tenant.campaigns.find(params[:id])
    campaign.update!(status: 'active')

    render json: { success: true, status: 'active' }
  end

  def test_send
    campaign = current_tenant.campaigns.find(params[:id])
    step = campaign.campaign_steps.first
    return render_error("Campaign has no email step") unless step

    UserMailer.campaign_email(current_api_user, current_tenant, step, current_location).deliver_later
    render json: { success: true, message: "Test email sent to #{current_api_user.email}" }
  end

  def destroy
    campaign = current_tenant.campaigns.find(params[:id])
    campaign.destroy

    render json: { success: true }
  end

  private

  def campaign_detail_json(campaign)
    step = campaign.campaign_steps.first
    {
      id: campaign.id,
      name: campaign.name,
      status: campaign.status,
      campaign_type: campaign.campaign_type,
      step_id: step&.id,
      subject: step&.subject,
      body: step&.body,
      segment: {
        customer_types: campaign.segment_customer_types,
        interest_products: campaign.segment_interest_products,
        interest_match: campaign.segment_interest_match,
      },
      recipient_count: campaign.recipient_count_for(current_location),
      scorecard: Campaigns::AttributionReport.new(campaign).scorecard,
      sent_at: campaign.sent_at&.iso8601,
      created_at: campaign.created_at.iso8601,
    }
  end

  def campaign_params
    params.permit(:name, :campaign_type, :status, :scheduled_at,
      segment: [:status_filter, :interest_match, customer_types: [], interest_products: [], date_range: [:from, :to]],
      campaign_steps_attributes: [:id, :subject, :body, :delay_days, :position, :_destroy])
  end
end

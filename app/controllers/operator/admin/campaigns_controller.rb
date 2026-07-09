class Operator::Admin::CampaignsController < Operator::BaseController
  before_action :require_authentication
  before_action :background_image
  before_action :find_campaign, only: [:show, :edit, :update, :destroy, :send_campaign, :pause, :resume, :clone, :preview, :test_send, :exclude_recipient]

  def index
    authorize Campaign
    @campaigns = Campaign.where(operator: current_tenant).order(created_at: :desc)
  end

  def new
    authorize Campaign
    @campaign = Campaign.new(campaign_type: "single")
    @campaign.campaign_steps.build(position: 0, delay_days: 0)
  end

  def create
    authorize Campaign
    @campaign = Campaign.new(campaign_params)
    @campaign.operator = current_tenant
    @campaign.location = current_location

    if @campaign.save
      flash[:notice] = "Campaign created."
      turbo_redirect(campaign_path(@campaign))
    else
      flash[:error] = @campaign.errors.full_messages.first || "Something went wrong."
      turbo_redirect(new_campaign_path)
    end
  end

  def show
    @recipient_count = @campaign.recipient_count_for(current_location)
    @spam_guard_excluded_count = @campaign.spam_guard_excluded_count_for(current_location)
    @recipients = @campaign.build_recipient_query(current_location).limit(50)
  end

  def edit
    @campaign.campaign_steps.build(position: @campaign.campaign_steps.count, delay_days: 0) if @campaign.campaign_steps.empty?
  end

  def update
    if @campaign.update(campaign_params)
      flash[:notice] = "Campaign updated."
      turbo_redirect(campaign_path(@campaign))
    else
      flash[:error] = @campaign.errors.full_messages.first || "Something went wrong."
      turbo_redirect(edit_campaign_path(@campaign))
    end
  end

  def destroy
    @campaign.destroy
    flash[:notice] = "Campaign deleted."
    turbo_redirect(campaigns_path)
  end

  def send_campaign
    if @campaign.draft? || @campaign.paused?
      @campaign.update!(status: "active", sent_at: Time.current)
      @campaign.update!(recipient_count: @campaign.recipient_count_for(current_location))
      SendCampaignJob.perform_later(@campaign.id, current_location.id)
      flash[:success] = "Campaign is being sent!"
    else
      flash[:error] = "Campaign cannot be sent in its current state."
    end
    turbo_redirect(campaign_path(@campaign))
  end

  def pause
    if @campaign.active?
      @campaign.update!(status: "paused")
      flash[:notice] = "Campaign paused."
    end
    turbo_redirect(campaign_path(@campaign))
  end

  def resume
    if @campaign.status == "paused"
      @campaign.update!(status: "active")
      SendCampaignJob.perform_later(@campaign.id, current_location.id)
      flash[:notice] = "Campaign resumed."
    end
    turbo_redirect(campaign_path(@campaign))
  end

  def clone
    new_campaign = @campaign.clone!
    flash[:notice] = "Campaign cloned. Edit your copy below."
    turbo_redirect(edit_campaign_path(new_campaign))
  end

  def preview
    @recipient_count = @campaign.recipient_count_for(current_location)
    @recipients = @campaign.build_recipient_query(current_location).limit(50)
    render layout: false
  end

  def exclude_recipient
    @campaign.exclude_user!(params[:user_id].to_i)
    flash[:notice] = "Removed from this campaign."
    turbo_redirect(campaign_path(@campaign))
  end

  def test_send
    step = @campaign.campaign_steps.first
    if step
      UserMailer.campaign_email(current_user, current_tenant, step, current_location).deliver_later
      flash[:notice] = "Test email sent to #{current_user.email}"
    else
      flash[:error] = "Campaign has no steps to send."
    end
    turbo_redirect(campaign_path(@campaign))
  end

  private

  def find_campaign
    # Tenant-scoped find (belt-and-suspenders with acts_as_tenant), then a role
    # check via CampaignPolicy — the controller had neither before.
    @campaign = current_tenant.campaigns.find(params[:id])
    authorize @campaign
  end

  def campaign_params
    params.require(:campaign).permit(
      :name, :campaign_type, :suppression_days, :cool_down_days, :scheduled_at,
      segment: [:status_filter, :interest_match, date_range: [:from, :to], customer_types: [], interest_products: []],
      campaign_steps_attributes: [:id, :position, :subject, :body, :delay_days, :_destroy]
    )
  end
end

class SendCampaignJob < ApplicationJob
  queue_as :default

  def perform(campaign_id, location_id)
    campaign = Campaign.find(campaign_id)
    location = Location.find(location_id)
    operator = campaign.operator

    return unless campaign.active?

    ActsAsTenant.with_tenant(operator) do
      if campaign.single?
        send_single(campaign, operator, location)
      else
        send_drip_step(campaign, operator, location)
      end
    end
  end

  private

  def send_single(campaign, operator, location)
    step = campaign.campaign_steps.first
    return unless step

    recipients = campaign.build_recipient_query(location)
    recipients = apply_suppression(recipients, campaign)

    sent = 0
    recipients.find_each do |user|
      next if CampaignSend.exists?(campaign_step: step, user: user)

      begin
        UserMailer.campaign_email(user, operator, step, location).deliver_later
        CampaignSend.create!(
          campaign: campaign, campaign_step: step, user: user,
          status: "sent", sent_at: Time.current
        )
        sent += 1
      rescue => e
        CampaignSend.create!(
          campaign: campaign, campaign_step: step, user: user,
          status: "failed", error_message: e.message
        )
        Honeybadger.notify(e, context: { campaign_id: campaign.id, user_id: user.id })
      end
    end

    step.update_column(:sent_count, step.campaign_sends.sent.count)
    campaign.update!(status: "completed", recipient_count: sent)
  end

  def send_drip_step(campaign, operator, location)
    recipients = campaign.build_recipient_query(location)
    recipients = apply_suppression(recipients, campaign)

    any_pending = false

    recipients.find_each do |user|
      # Find the next unsent step for this user
      campaign.campaign_steps.each do |step|
        next if CampaignSend.exists?(campaign_step: step, user: user)

        # Check if enough time has passed since campaign start or last step
        if step.position == 0
          # First step: send immediately
        else
          # Check delay from previous step's send time
          prev_step = campaign.campaign_steps.find_by(position: step.position - 1)
          prev_send = CampaignSend.find_by(campaign_step: prev_step, user: user, status: "sent")
          next unless prev_send
          next unless prev_send.sent_at + step.delay_days.days <= Time.current
        end

        begin
          UserMailer.campaign_email(user, operator, step, location).deliver_later
          CampaignSend.create!(
            campaign: campaign, campaign_step: step, user: user,
            status: "sent", sent_at: Time.current
          )
        rescue => e
          CampaignSend.create!(
            campaign: campaign, campaign_step: step, user: user,
            status: "failed", error_message: e.message
          )
        end

        any_pending = true
        break # Only one step per user per run
      end

      # Check if user has received all steps
      unless any_pending
        all_sent = campaign.campaign_steps.all? { |s| CampaignSend.exists?(campaign_step: s, user: user) }
        any_pending = true unless all_sent
      end
    end

    # Update step counts
    campaign.campaign_steps.each do |step|
      step.update_column(:sent_count, step.campaign_sends.sent.count)
    end

    # Mark complete if all users received all steps
    unless any_pending
      campaign.update!(status: "completed")
    end
  end

  def apply_suppression(recipients, campaign)
    return recipients if campaign.suppression_days.nil? || campaign.suppression_days == 0

    recently_contacted_ids = CampaignSend
      .where(status: "sent")
      .where("sent_at > ?", campaign.suppression_days.days.ago)
      .where.not(campaign_id: campaign.id)
      .select(:user_id)

    recipients.where.not(id: recently_contacted_ids)
  end
end

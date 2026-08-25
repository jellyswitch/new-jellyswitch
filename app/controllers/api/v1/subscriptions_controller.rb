class Api::V1::SubscriptionsController < Api::V1::BaseController
  # Member-selectable churn reasons (mobile cancel flow). Key = API param value;
  # label lands in the admin feed text and the suppression reason.
  CHURN_REASONS = {
    "moving_away"   => "Moving away",
    "just_visiting" => "Was just visiting",
    "too_expensive" => "Too expensive",
    "not_using"     => "Not using it enough",
    "other"         => "Something else",
  }.freeze
  # Reasons that mean the member is gone for good — stop marketing to them.
  # Price/usage churners stay sendable so past-member win-back can target them.
  SUPPRESSING_REASONS = %w(moving_away just_visiting).freeze

  def plans
    categories = PlanCategory.where(operator: current_tenant).order(:name)
    plans = Plan.where(operator: current_tenant, available: true, visible: true, plan_type: 'individual')
      .where(location: current_location)
      .order(:amount_in_cents)
      # Grandfathering: an active member never sees a costlier same-name version
      # of the tier they already hold (keeps their locked-in price).
      .switchable_from(current_api_user.subscriptions.where(active: true).first&.plan)

    render json: {
      categories: categories.map { |c| { id: c.id, name: c.name } },
      plans: plans.map { |p| plan_json(p) },
    }
  end

  def my_subscription
    sub = current_api_user.subscriptions.where(active: true).first
    if sub
      render json: subscription_json(sub)
    else
      render json: { subscription: nil }
    end
  end

  def create
    plan = Plan.find(params[:plan_id])
    start_day = params[:start_date].present? ? Date.parse(params[:start_date]) : Date.current

    subscription = Subscription.new(
      plan: plan,
      subscribable: current_api_user,
    )

    # Choose interactor based on whether user has payment method
    token = params[:stripe_token]
    if token.present?
      result = Billing::Subscription::UpdatePaymentAndCreateSubscription.call(
        subscription: subscription,
        token: token,
        user: current_api_user,
        start_day: start_day,
        operator: current_tenant,
        location: current_location,
      )
    else
      result = Billing::Subscription::CreateSubscription.call(
        subscription: subscription,
        user: current_api_user,
        start_day: start_day,
        operator: current_tenant,
        location: current_location,
      )
    end

    if result.success?
      render json: subscription_json(result.subscription), status: :created
    else
      render_error(result.message || 'Unable to create subscription')
    end
  end

  def pause
    sub = current_api_user.subscriptions.find(params[:id])
    days = params[:resumes_at].to_i
    resumes_at = days.days.from_now.to_i

    result = CreatePause.call(
      subscription: sub,
      resumes_at: resumes_at,
      operator: current_tenant,
      user: current_api_user,
      notifiable: sub,
      blob: { text: "Paused for #{days} days via mobile app", type: "membership_paused" },
    )

    if result.success?
      render json: { success: true, message: "Membership paused for #{days} days." }
    else
      render_error(result.message || 'Unable to pause membership')
    end
  rescue ActiveRecord::RecordNotFound
    render_error('Subscription not found', status: :not_found)
  end

  def unpause
    sub = current_api_user.subscriptions.find(params[:id])

    result = DestroyPause.call(
      subscription: sub,
      operator: current_tenant,
      user: current_api_user,
      notifiable: sub,
      blob: { text: "Unpaused via mobile app", type: "membership_unpaused" },
    )

    if result.success?
      render json: { success: true, message: 'Membership resumed.' }
    else
      render_error(result.message || 'Unable to unpause membership')
    end
  rescue ActiveRecord::RecordNotFound
    render_error('Subscription not found', status: :not_found)
  end

  def upgrade
    old_sub = current_api_user.subscriptions.find(params[:id])
    return if reject_office_lease_change(old_sub)

    # Pre-flight: Stripe::Subscription.update on a paused subscription
    # raises Stripe::InvalidRequestError ("Cannot update a subscription
    # whose status is paused"), which used to bubble all the way up as
    # a 500 / "Internal server error" alert on the mobile client.
    # Return a friendly, actionable message instead.
    if old_sub.paused?
      return render_error(
        "Your membership is paused. Please unpause it first to switch plans.",
        status: :unprocessable_entity,
      )
    end

    new_plan = Plan.find(params[:plan_id])

    # Grandfathering guard: block switching to the plan they're already on (a
    # no-op) or to a costlier same-name version of their tier (which would lose
    # their locked-in price). Switching to a different tier is still allowed.
    if new_plan.blocks_switch_from?(old_sub.plan)
      return render_error(
        "You're already on the #{old_sub.plan.name} plan at your current price.",
        status: :unprocessable_entity,
      )
    end

    new_sub = Subscription.new(
      plan: new_plan,
      subscribable: current_api_user,
    )

    result = UpdateMembership.call(
      old_subscription: old_sub,
      new_subscription: new_sub,
      blob: { text: "Upgraded via mobile app", type: "membership_updated" },
      user: current_api_user,
      operator: current_tenant,
      location: current_location,
      notifiable: old_sub,
    )

    if result.success?
      render json: subscription_json(result.try(:subscription) || new_sub)
    else
      render_error(result.message || 'Unable to upgrade membership')
    end
  rescue ActiveRecord::RecordNotFound
    render_error('Subscription or plan not found', status: :not_found)
  end

  def cancel_now
    sub = current_api_user.subscriptions.find(params[:id])
    return if reject_office_lease_change(sub)

    # A committed member can't cancel immediately — schedule the end at their
    # current commitment boundary instead. Admins override via the operator API.
    if sub.in_commitment?
      sub.schedule_commitment_cancellation!
      auto_suppress_for_churn!
      ends_on = sub.commitment_term_end&.strftime("%B %e, %Y")
      record_scheduled_churn_reason(sub, ends_on)
      send_commitment_cancellation_email(sub)
      return render json: {
        success: true,
        scheduled: true,
        ends_on: ends_on,
        message: "Your membership is committed through #{ends_on} and will end then.",
      }
    end

    result = Billing::Subscription::CancelSubscriptionNow.call(
      subscription: sub,
      blob: { text: with_churn_reason("Cancelled #{sub.plan.name} membership immediately via mobile app."), type: "membership_cancellation" },
      user: current_api_user,
      operator: current_tenant,
      location: current_location,
      notifiable: sub,
      creditable: current_api_user,
    )

    if result.success?
      auto_suppress_for_churn!
      render json: { success: true, message: 'Membership cancelled immediately.' }
    else
      render_error(result.message || 'Unable to cancel immediately')
    end
  rescue ActiveRecord::RecordNotFound
    render_error('Subscription not found', status: :not_found)
  end

  def destroy
    sub = current_api_user.subscriptions.find(params[:id])
    return if reject_office_lease_change(sub)

    # A committed member can't cancel early — schedule the end at their
    # commitment boundary instead of the end of the current billing period.
    # Mirrors #cancel_now (this scheduled path had been missing the guard, so a
    # committed member could still end at month-end). Admins override via the
    # operator API.
    if sub.in_commitment?
      sub.schedule_commitment_cancellation!
      auto_suppress_for_churn!
      ends_on = sub.commitment_term_end&.strftime("%B %e, %Y")
      record_scheduled_churn_reason(sub, ends_on)
      send_commitment_cancellation_email(sub)
      return render json: {
        success: true,
        scheduled: true,
        ends_on: ends_on,
        message: "Your membership is committed through #{ends_on} and will end then.",
      }
    end

    result = SetSubscriptionForCancellation.call(
      subscription: sub,
      blob: { text: with_churn_reason("Cancelled via mobile app."), type: "membership_cancellation" },
      user: current_api_user,
      operator: current_tenant,
      location: current_location,
      notifiable: sub,
    )

    if result.success?
      auto_suppress_for_churn!
      render json: { success: true, message: 'Membership will cancel at end of billing period.' }
    else
      render_error(result.message || 'Unable to cancel')
    end
  rescue ActiveRecord::RecordNotFound
    render_error('Subscription not found', status: :not_found)
  end

  private

  def churn_reason_label
    CHURN_REASONS[params[:reason].to_s]
  end

  # Append the member's stated reason to a cancellation feed blob so staff see
  # it where they already see the cancel. Unknown/absent reasons change nothing.
  def with_churn_reason(text)
    churn_reason_label ? "#{text} Reason: #{churn_reason_label}." : text
  end

  # A mover/tourist is gone for good — auto-suppress marketing (Phase 1b) so
  # campaigns and win-back stop targeting them. Never clobbers an existing
  # suppression, and never lets a suppression hiccup break the cancel response.
  # update_columns: unrelated User validation drift must not skip this write.
  # The "Churned:" prefix marks it machine-set — re-subscribing clears it
  # (Subscription#clear_churn_suppression) while admin suppressions stay.
  def auto_suppress_for_churn!
    return unless SUPPRESSING_REASONS.include?(params[:reason].to_s)
    return if current_api_user.marketing_suppressed?

    current_api_user.update_columns(
      marketing_suppressed: true,
      marketing_suppressed_reason: "Churned: #{churn_reason_label}",
      updated_at: Time.current,
    )
  rescue => e
    Honeybadger.notify(e, context: { user_id: current_api_user.id, reason: params[:reason] })
  end

  # The commitment-scheduled path creates no cancellation feed item (the end is
  # months away), which would silently drop a stated reason — the only place it
  # is recorded for staff. Post one when (and only when) a reason was given.
  def record_scheduled_churn_reason(sub, ends_on)
    return unless churn_reason_label

    FeedItemCreator.create_feed_item(
      current_tenant,
      current_location,
      current_api_user,
      { text: "Scheduled cancellation of #{sub.plan.name} membership at commitment end (#{ends_on}) via mobile app. Reason: #{churn_reason_label}.",
        type: "membership_cancellation" },
    )
  rescue => e
    Honeybadger.notify(e, context: { user_id: current_api_user.id, reason: params[:reason] })
  end

  # The commitment-scheduled path bypasses both cancellation organizers, so
  # without this the member would get no written confirmation at all — only the
  # in-app alert (Marian Sterk, TLH 7/26). The interactor states that billing
  # continues through the commitment boundary and swallows delivery failures,
  # so a mail hiccup can never break the cancel response.
  def send_commitment_cancellation_email(sub)
    Billing::Subscription::SendCancellationConfirmation.call(
      subscription: sub,
      user: current_api_user,
      operator: current_tenant,
      location: current_location,
      commitment_ends_on: sub.commitment_term_end,
    )
  end

  # Office leases are fixed-term contracts — a member can't self-cancel or
  # downgrade the subscription backing one from the app (only an admin
  # terminates via the office-lease flow). Returns true (and renders 403) when
  # the action should be blocked, so callers do `return if reject_...`.
  def reject_office_lease_change(sub)
    return false unless sub&.backs_office_lease?

    render_error(
      "This subscription is part of an office lease — a fixed-term agreement. " \
      "Please contact your host to make changes to it.",
      status: :forbidden,
    )
    true
  end

  def plan_json(plan)
    {
      id: plan.id,
      name: plan.name,
      amount: plan.amount_in_cents,
      interval: plan.interval,
      category: plan.plan_category&.name,
      features: plan.try(:description),
    }
  end

  def subscription_json(sub)
    plan = sub.plan
    period_start, period_end = sub.try(:current_billing_period) || [nil, nil]

    {
      id: sub.id,
      plan_name: plan.name,
      amount: plan.amount_in_cents,
      interval: plan.interval,
      start_date: sub.start_date&.strftime("%B %e, %Y"),
      end_date: sub.try(:end_date)&.strftime("%B %e, %Y"),
      period_end_date: period_end&.strftime("%B %e, %Y"),
      active: sub.active?,
      pending: sub.pending?,
      paused: sub.try(:paused?) || false,
      cancelling: sub.cancelling_at_end_of_billing_period?,
      days_left: plan.try(:has_day_limit?) ? sub.try(:days_left) : nil,
      day_limit: plan.try(:has_day_limit?) ? plan.day_limit : nil,
      days_used: plan.try(:has_day_limit?) ? sub.try(:day_pool_used) : nil,
      # Commitment (minimum term) — lets the app show "Committed through {date}"
      # and frame the cancel action as scheduling an end at the boundary.
      in_commitment: sub.try(:in_commitment?) || false,
      commitment_ends_on: (sub.commitment_term_end&.strftime("%B %e, %Y") if sub.try(:in_commitment?)),
      # Office leases are admin-managed contracts — the app hides the
      # cancel/change-plan affordances when this is true (server still enforces).
      is_office_lease: sub.try(:backs_office_lease?) || false,
      # The location's house rule about pausing, shown as a confirm before the
      # app pauses anything (a Tahoe Longhouse member paused from the app and
      # left a dedicated desk full of belongings behind, 2026-08-19). nil =
      # nothing to warn about; the app pauses straight through.
      pause_warning: plan.location&.pause_warning.presence,
      # Day Pool resets with the billing period; period_end_date above is that date.
      included_meeting_minutes: plan.try(:included_meeting_room_minutes),
      billed_to: sub.subscribable_type == 'Organization' ? 'organization' : 'user',
    }
  end
end

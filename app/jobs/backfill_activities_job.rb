class BackfillActivitiesJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 1_000

  def perform(operator_id, since: 2.years.ago)
    operator = Operator.find(operator_id)

    backfill_reservations(operator, since)
    backfill_checkins(operator, since)
    backfill_door_punches(operator, since)
    backfill_day_passes(operator, since)
    backfill_day_pass_bundles(operator, since)
    backfill_subscriptions(operator, since)
    backfill_invoices(operator, since)
    backfill_lead_notes(operator, since)
    backfill_user_signups(operator, since)
    backfill_campaign_email_sends(operator, since)

    operator.update_columns(last_activities_backfilled_at: Time.current)
  end

  private

  def log_unless_exists(kind:, source:, user:, occurred_at:, operator:)
    return if user.nil?
    return if Activity.where(subject_type: source.class.name, subject_id: source.id, kind: kind.to_s).exists?

    Activity.log(
      user: user,
      operator: operator,
      kind: kind,
      subject: source,
      occurred_at: occurred_at,
    )
  end

  def backfill_reservations(operator, since)
    Reservation.joins(room: :location)
      .where(locations: { operator_id: operator.id })
      .where("reservations.created_at >= ?", since)
      .find_each(batch_size: BATCH_SIZE) do |reservation|
        log_unless_exists(
          kind: :reservation,
          source: reservation,
          user: reservation.user,
          occurred_at: reservation.created_at,
          operator: operator,
        )
      end
  end

  def backfill_checkins(operator, since)
    Checkin.joins(:location)
      .where(locations: { operator_id: operator.id })
      .where("checkins.created_at >= ?", since)
      .find_each(batch_size: BATCH_SIZE) do |checkin|
        log_unless_exists(
          kind: :checkin,
          source: checkin,
          user: checkin.user,
          occurred_at: checkin.created_at,
          operator: operator,
        )
      end
  end

  def backfill_door_punches(operator, since)
    DoorPunch.where(operator_id: operator.id)
      .where("created_at >= ?", since)
      .find_each(batch_size: BATCH_SIZE) do |punch|
        log_unless_exists(
          kind: :door_punch,
          source: punch,
          user: punch.user,
          occurred_at: punch.created_at,
          operator: operator,
        )
      end
  end

  def backfill_day_passes(operator, since)
    DayPass.where(operator_id: operator.id)
      .where("created_at >= ?", since)
      .find_each(batch_size: BATCH_SIZE) do |day_pass|
        log_unless_exists(
          kind: :day_pass,
          source: day_pass,
          user: day_pass.user,
          occurred_at: day_pass.created_at,
          operator: operator,
        )
      end
  end

  # Bundles only started logging their own activity when the timeline began
  # reporting passes-used and hours-booked per pack, so every pack bought
  # before that has no card. purchased_at is the real buy moment; created_at
  # backs it up for rows seeded or imported without one.
  def backfill_day_pass_bundles(operator, since)
    DayPassBundle.where(operator_id: operator.id)
      .where("created_at >= ?", since)
      .find_each(batch_size: BATCH_SIZE) do |bundle|
        log_unless_exists(
          kind: :day_pass_bundle,
          source: bundle,
          user: bundle.user,
          occurred_at: bundle.purchased_at || bundle.created_at,
          operator: operator,
        )
      end
  end

  # Subscriptions: only backfill User-subscribable rows (Organizations are out
  # of scope for the per-Person timeline). For ended subscriptions we use
  # updated_at as the best-available proxy for cancellation time — Stripe knows
  # the real timestamp but we don't store it locally.
  def backfill_subscriptions(operator, since)
    user_ids = operator.users.pluck(:id)
    return if user_ids.empty?

    Subscription.where(subscribable_type: "User", subscribable_id: user_ids)
      .where("created_at >= ?", since)
      .find_each(batch_size: BATCH_SIZE) do |sub|
        log_unless_exists(
          kind: :subscription_started,
          source: sub,
          user: sub.subscribable,
          occurred_at: sub.created_at,
          operator: operator,
        )

        next if sub.active?

        log_unless_exists(
          kind: :subscription_ended,
          source: sub,
          user: sub.subscribable,
          occurred_at: sub.updated_at,
          operator: operator,
        )
      end
  end

  def backfill_invoices(operator, since)
    Invoice.where(operator_id: operator.id, billable_type: "User")
      .where("created_at >= ?", since)
      .find_each(batch_size: BATCH_SIZE) do |invoice|
        kind = case invoice.status
               when "paid" then :payment_succeeded
               when "uncollectible" then :payment_failed
               end
        next unless kind

        log_unless_exists(
          kind: kind,
          source: invoice,
          user: invoice.billable,
          occurred_at: invoice.updated_at,
          operator: operator,
        )
      end
  end

  def backfill_lead_notes(operator, since)
    LeadNote.joins(:lead)
      .where(leads: { operator_id: operator.id })
      .where("lead_notes.created_at >= ?", since)
      .find_each(batch_size: BATCH_SIZE) do |note|
        log_unless_exists(
          kind: :note,
          source: note,
          user: note.lead.user,
          occurred_at: note.created_at,
          operator: operator,
        )
      end
  end

  def backfill_user_signups(operator, since)
    User.where(operator_id: operator.id)
      .where("created_at >= ?", since)
      .find_each(batch_size: BATCH_SIZE) do |user|
        log_unless_exists(
          kind: :signup,
          source: user,
          user: user,
          occurred_at: user.created_at,
          operator: operator,
        )
      end
  end

  # CampaignSend is the only email source with a meaningful history pre-Phase-1
  # (transactional emails weren't logged). Per CONTEXT.md, email_opened/clicked/
  # replied cannot be backfilled — they start counting from ship day.
  def backfill_campaign_email_sends(operator, since)
    CampaignSend.joins(:campaign)
      .where(campaigns: { operator_id: operator.id })
      .where(status: "sent")
      .where("campaign_sends.sent_at >= ?", since)
      .find_each(batch_size: BATCH_SIZE) do |send|
        log_unless_exists(
          kind: :email_sent,
          source: send,
          user: send.user,
          occurred_at: send.sent_at || send.created_at,
          operator: operator,
        )
      end
  end
end

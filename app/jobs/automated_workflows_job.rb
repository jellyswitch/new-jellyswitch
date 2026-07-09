class AutomatedWorkflowsJob < ApplicationJob
  queue_as :default

  def perform
    Operator.where(billing_state: "production").find_each do |operator|
      operator.locations.each do |location|
        next unless location.visible?

        ActsAsTenant.with_tenant(operator) do
          Time.use_zone(location.time_zone) do
            next if quiet_hours?
            process_workflows(operator, location)
          end
        end
      end
    end
  end

  private

  def quiet_hours?
    hour = Time.current.hour
    hour >= 21 || hour < 9 # 9pm to 9am
  end

  def process_workflows(operator, location)
    workflows = AutomatedWorkflow.where(operator: operator, location: location, enabled: true)

    workflows.each do |workflow|
      case workflow.workflow_type
      when "re_engagement"
        run_re_engagement(workflow, operator, location)
      when "past_due_followup"
        run_past_due_followup(workflow, operator, location)
      when "booking_reminder"
        run_booking_reminder(workflow, operator, location)
      when "day_passer_followup"
        run_day_passer_followup(workflow, operator, location)
      when "room_reservation_followup"
        run_room_reservation_followup(workflow, operator, location)
      when "past_member_recovery"
        run_past_member_recovery(workflow, operator, location)
      end
    rescue => e
      Rails.logger.error("AutomatedWorkflow #{workflow.workflow_type} failed: #{e.message}")
      Honeybadger.notify(e, context: { workflow_id: workflow.id, workflow_type: workflow.workflow_type })
    end
  end

  # Re-engagement: email members with no reservations or door punches in X days
  def run_re_engagement(workflow, operator, location)
    days = workflow.days_inactive
    cutoff = days.days.ago

    users = User.for_space(operator)
      .originally_at_location(location)
      .approved
      .visible
      .marketing_sendable
      .joins(:subscriptions)
      .where(subscriptions: { pending: false })
      .distinct

    # Was product_type: "re_engagement" (not a valid product_type) + the wrong
    # email_type — so this never matched and the workflow never sent. Member
    # re-engagement uses the membership/re_engagement template.
    template = ProductEmailTemplate.find_by(
      operator: operator, location: location,
      product_type: "membership", email_type: "re_engagement"
    )
    return unless template&.enabled?

    users.find_each do |user|
      next if user.reservations.where("created_at > ?", cutoff).exists?
      next if user.door_punches.where("created_at > ?", cutoff).exists?

      # Use the same key-based ledger as every other handler. The old
      # record_send helper never set the (required) user_id, so the send row
      # silently failed to persist — meaning no dedup and no attribution. The
      # per-day key plus SpamGuard's 30-day cool-down throttle re-sends.
      send_key = "re_engagement_#{user.id}_#{Date.current}"
      next if already_sent_key?(send_key)
      next unless guard_eligible?(user, operator, send_key)

      UserMailer.re_engagement_email(user, operator, template, location).deliver_later
      record_send_key(user, send_key)
    end
  end

  # Past-due: follow-up emails at day 3, 7, 14 for unpaid invoices
  def run_past_due_followup(workflow, operator, location)
    followup_days = workflow.followup_days

    Invoice.where(operator: operator, location: location, status: "open")
      .where.not(due_date: nil)
      .where("due_date < ?", Time.current)
      .find_each do |invoice|
        user = invoice.billable
        next unless user.is_a?(User)
        next if user.email_opted_out? || user.email_bounced? || user.marketing_suppressed?

        days_past_due = (Date.current - invoice.due_date.to_date).to_i

        followup_days.each do |day|
          next unless days_past_due >= day
          send_key = "past_due_day_#{day}_invoice_#{invoice.id}"
          next if already_sent_key?(send_key)

          UserMailer.past_due_followup_email(user, operator, invoice, location).deliver_later
          record_send_key(user, send_key)
        end
      end
  end

  # Booking reminder: email 24h before paid room reservations
  def run_booking_reminder(workflow, operator, location)
    hours = workflow.hours_before
    window_start = hours.hours.from_now
    window_end = (hours + 1).hours.from_now

    reservations = Reservation.joins(:room)
      .where(rooms: { location_id: location.id })
      .where(datetime_in: window_start..window_end)
      .includes(:user, :room)

    reservations.find_each do |reservation|
      user = reservation.user
      next if user.email_opted_out? || user.email_bounced? || user.marketing_suppressed?
      # Only remind people who actually paid for the reservation. Members on
      # plans, day-pass holders, lease holders, admins, GMs, and CMs all book
      # rentable rooms with reservation.paid = false (see Billing::Reservations::SaveRoomReservation).
      next unless reservation.paid?

      send_key = "booking_reminder_#{reservation.id}"
      next if already_sent_key?(send_key)

      UserMailer.booking_reminder_email(user, operator, reservation, location).deliver_later
      record_send_key(user, send_key)
    end
  end

  # Day-passer follow-up: email day-passers N days after their visit if they
  # haven't returned (no day_pass / reservation / checkin / door_punch since).
  # Skips current members (they're already engaged).
  def run_day_passer_followup(workflow, operator, location)
    days_after = workflow.days_after
    target_date = days_after.days.ago.to_date

    template = ProductEmailTemplate.find_by(
      operator: operator, location: location,
      product_type: "day_pass", email_type: "re_engagement"
    )
    return unless template&.enabled?

    DayPass.where(operator: operator, location: location, day: target_date)
           .not_bundle_sourced
           .includes(:user)
           .find_each do |day_pass|
      user = day_pass.user
      next unless user
      next if user.email_opted_out? || user.email_bounced? || user.marketing_suppressed?
      next if user.has_active_subscription?
      next if returned_since?(user, day_pass.day)

      send_key = "day_passer_followup_#{day_pass.id}"
      next if already_sent_key?(send_key)
      next unless guard_eligible?(user, operator, send_key)

      UserMailer.re_engagement_email(user, operator, template, location).deliver_later
      record_send_key(user, send_key)
    end
  end

  # Room-reservation follow-up: same shape but driven off Reservation rows.
  def run_room_reservation_followup(workflow, operator, location)
    days_after = workflow.days_after
    target_window_start = (days_after + 1).days.ago.beginning_of_day
    target_window_end = days_after.days.ago.end_of_day

    template = ProductEmailTemplate.find_by(
      operator: operator, location: location,
      product_type: "reservation", email_type: "re_engagement"
    )
    return unless template&.enabled?

    Reservation.joins(:room)
               .where(rooms: { location_id: location.id })
               .where(cancelled: false)
               .where(datetime_in: target_window_start..target_window_end)
               .includes(:user, :room)
               .find_each do |reservation|
      user = reservation.user
      next unless user
      next if user.email_opted_out? || user.email_bounced? || user.marketing_suppressed?
      next if user.has_active_subscription?
      next if returned_since?(user, reservation.datetime_in.to_date)

      send_key = "room_reservation_followup_#{reservation.id}"
      next if already_sent_key?(send_key)
      next unless guard_eligible?(user, operator, send_key)

      UserMailer.re_engagement_email(user, operator, template, location).deliver_later
      record_send_key(user, send_key)
    end
  end

  # Past-member recovery: email former members `days_after_grace` days AFTER
  # `location.past_member_grace_days` has expired. Skips current members.
  def run_past_member_recovery(workflow, operator, location)
    days_after_grace = workflow.days_after_grace
    grace_days = location.past_member_grace_days
    target_date = (grace_days + days_after_grace).days.ago.to_date

    template = ProductEmailTemplate.find_by(
      operator: operator, location: location,
      product_type: "membership", email_type: "past_member_recovery"
    )
    return unless template&.enabled?

    # Find users whose most-recent subscription_ended Activity was on target_date.
    activity_users = Activity.where(kind: "subscription_ended", operator: operator)
                             .where("DATE(occurred_at AT TIME ZONE 'UTC') = ?", target_date)
                             .pluck(:user_id)
                             .uniq

    User.where(id: activity_users)
        .marketing_sendable
        .find_each do |user|
      next if user.has_active_subscription?

      send_key = "past_member_recovery_#{user.id}_#{target_date}"
      next if already_sent_key?(send_key)
      next unless guard_eligible?(user, operator, send_key)

      UserMailer.re_engagement_email(user, operator, template, location).deliver_later
      record_send_key(user, send_key)
    end
  end

  def returned_since?(user, since_date)
    user.day_passes.where("day > ?", since_date).exists? ||
      user.reservations.where("datetime_in > ?", since_date.to_time).exists? ||
      user.checkins.where("datetime_in > ?", since_date.to_time).exists? ||
      user.door_punches.where("created_at > ?", since_date.to_time).exists?
  end

  # Returns true if SpamGuard says we're clear to send. Otherwise records a
  # ProductEmailSend with status="skipped" + reason so the send_log shows
  # what got filtered. cool_down_days defaults to 30 — Phase 8.2 may add
  # per-workflow overrides.
  def guard_eligible?(user, operator, send_key, cool_down_days: 30)
    return true if SpamGuard.eligible?(user, sender: operator, cool_down_days: cool_down_days)
    log_skip(user, operator, send_key, "Skipped by Spam Guard (in active series or within cool-down)")
    false
  end

  def log_skip(user, operator, send_key, reason)
    ProductEmailSend.create!(
      operator: operator,
      user: user,
      sendable: user,
      email_type: send_key,
      status: "skipped",
      error_message: reason,
      sent_at: Time.current,
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # Already logged — fine.
  end

  def already_sent_key?(key)
    ProductEmailSend.where(email_type: key).exists?
  end

  def record_send_key(user, key)
    ProductEmailSend.create!(
      user: user,
      sendable: user,
      email_type: key,
      status: "sent",
      sent_at: Time.current,
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # Already sent (unique index covers the dedup case)
  end
end

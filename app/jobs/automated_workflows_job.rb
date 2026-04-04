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
      when "signup_nurture"
        run_signup_nurture(workflow, operator, location)
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
      .where(email_opted_out: false, email_bounced: false)
      .joins(:subscriptions)
      .where(subscriptions: { pending: false })
      .distinct

    template = ProductEmailTemplate.find_by(
      operator: operator, location: location,
      product_type: "re_engagement", email_type: "onboarding"
    )
    return unless template&.enabled?

    users.find_each do |user|
      next if user.reservations.where("created_at > ?", cutoff).exists?
      next if user.door_punches.where("created_at > ?", cutoff).exists?
      next if already_sent?(user, "re_engagement", days)

      UserMailer.re_engagement_email(user, operator, template, location).deliver_later
      record_send(user, "re_engagement", "onboarding")
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
        next if user.email_opted_out? || user.email_bounced?

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
      next if user.email_opted_out? || user.email_bounced?
      next unless reservation.room.rentable? # paid rooms only

      send_key = "booking_reminder_#{reservation.id}"
      next if already_sent_key?(send_key)

      UserMailer.booking_reminder_email(user, operator, reservation, location).deliver_later
      record_send_key(user, send_key)
    end
  end

  # Signup nurture: drip sequence for users who signed up but haven't purchased
  def run_signup_nurture(workflow, operator, location)
    sequence_days = workflow.sequence_days

    users = User.for_space(operator)
      .originally_at_location(location)
      .visible
      .where(email_opted_out: false, email_bounced: false)

    users.find_each do |user|
      next if user.day_passes.any? || user.subscriptions.any? || user.reservations.any?

      days_since_signup = (Date.current - user.created_at.to_date).to_i

      sequence_days.each_with_index do |day, step|
        next unless days_since_signup >= day

        template = ProductEmailTemplate.find_by(
          operator: operator, location: location,
          product_type: "signup_nurture", email_type: "nurture_step_#{step}"
        )
        next unless template&.enabled?

        send_key = "signup_nurture_step_#{step}_user_#{user.id}"
        next if already_sent_key?(send_key)

        UserMailer.re_engagement_email(user, operator, template, location).deliver_later
        record_send_key(user, send_key)
        break # only send one step per run
      end
    end
  end

  def already_sent?(user, product_type, cooldown_days)
    ProductEmailSend.where(
      sendable: user,
      product_type: product_type
    ).where("created_at > ?", cooldown_days.days.ago).exists?
  end

  def already_sent_key?(key)
    ProductEmailSend.where(email_type: key).exists?
  end

  def record_send(user, product_type, email_type)
    ProductEmailSend.create(
      sendable: user,
      product_type: product_type,
      email_type: email_type,
      status: "sent"
    )
  rescue ActiveRecord::RecordNotUnique
    # Already sent
  end

  def record_send_key(user, key)
    ProductEmailSend.create(
      sendable: user,
      product_type: "automation",
      email_type: key,
      status: "sent"
    )
  rescue ActiveRecord::RecordNotUnique
    # Already sent
  end
end

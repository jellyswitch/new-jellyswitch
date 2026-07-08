class SendProductEmailJob < ApplicationJob
  queue_as :default

  def perform(sendable_type, sendable_id, operator_id, product_type, email_type, user_id)
    operator = Operator.find_by(id: operator_id)
    return unless operator

    ActsAsTenant.with_tenant(operator) do
      user = User.find_by(id: user_id)
      return unless user

      # Find the sendable (could be DayPass, Reservation, User, etc.)
      sendable = sendable_type.constantize.find_by(id: sendable_id)
      return unless sendable

      # Resolve the location from the sendable
      location = resolve_location(sendable, user)

      # Find the template scoped to the location
      template = ProductEmailTemplate.find_by(
        operator: operator,
        location: location,
        product_type: product_type,
        email_type: email_type
      )
      return unless template&.enabled? && template.body.present?

      # Duplicate check
      return if ProductEmailSend.already_sent?(sendable, email_type)

      # For signup nudge: skip if user has made any purchases
      if email_type == "nudge"
        return if user.day_passes.any? ||
                   user.subscriptions.any? ||
                   Reservation.where(user: user).any?
      end

      # For follow-ups: skip if sendable is cancelled/inactive. A bundle is
      # exempt — its active?/passes_remaining state is not a cancellation: a
      # small pack can be emptied on the very first visit, and we still want to
      # send the "how was your visit?" review.
      if email_type == "follow_up" && !sendable.is_a?(DayPassBundle)
        return if sendable.respond_to?(:cancelled?) && sendable.cancelled?
        return if sendable.respond_to?(:active?) && !sendable.active?
      end

      # Honor unsubscribe / marketing suppression. These sends are scheduled
      # ahead of time (the signup nudge fires ~a day after signup), so the
      # recipient may have unsubscribed in the interim — re-check at send time.
      # Onboarding is transactional (welcome / "your booking is confirmed") and
      # always sends. SpamGuard only checks frequency, not opt-out.
      if email_type != "onboarding" && (user.email_opted_out? || user.marketing_suppressed?)
        ProductEmailSend.create!(
          operator: operator, user: user, sendable: sendable,
          email_type: email_type, status: "skipped",
          error_message: "Skipped: recipient unsubscribed or marketing-suppressed",
          sent_at: Time.current,
        )
        return
      end

      # SpamGuard (ADR-0003): gate all marketing-type sends. Onboarding is
      # operationally-required (welcome / "your booking is confirmed"
      # information) and always sends — gating it would create confusing UX
      # gaps right after a purchase.
      if email_type != "onboarding" && !SpamGuard.eligible?(user, sender: operator, cool_down_days: 30)
        ProductEmailSend.create!(
          operator: operator, user: user, sendable: sendable,
          email_type: email_type, status: "skipped",
          error_message: "Skipped by Spam Guard (in active series or within cool-down)",
          sent_at: Time.current,
        )
        return
      end

      # Send the email
      begin
        case email_type
        when "onboarding"
          UserMailer.product_onboarding_email(user, operator, template, sendable, location).deliver_now
        when "follow_up", "replenishment"
          # Bundle review + replenishment reuse the follow-up mailer (subject +
          # body come from the template; the merge tags differ per product type).
          UserMailer.product_follow_up_email(user, operator, template, sendable, location).deliver_now
        when "nudge"
          UserMailer.signup_nudge_email(user, operator, template, location).deliver_now
        end

        ProductEmailSend.create!(
          operator: operator,
          user: user,
          sendable: sendable,
          email_type: email_type,
          status: "sent",
          sent_at: Time.current
        )
      rescue => e
        Honeybadger.notify(e)
        Rails.logger.error("SendProductEmailJob failed: #{e.class}: #{e.message}")

        ProductEmailSend.create!(
          operator: operator,
          user: user,
          sendable: sendable,
          email_type: email_type,
          status: "failed",
          error_message: e.message,
          sent_at: Time.current
        )
      end
    end
  end

  private

  def resolve_location(sendable, user)
    case sendable
    when DayPass, DayPassBundle
      sendable.location
    when Reservation
      sendable.room&.location
    when OfficeLease
      sendable.location
    when Subscription
      sendable.plan&.location
    when User
      Location.find_by(id: sendable.original_location_id)
    else
      Location.find_by(id: user.original_location_id)
    end
  end
end

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

      # Find the template
      template = ProductEmailTemplate.find_by(
        operator: operator,
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

      # For follow-ups: skip if sendable is cancelled/inactive
      if email_type == "follow_up"
        return if sendable.respond_to?(:cancelled?) && sendable.cancelled?
        return if sendable.respond_to?(:active?) && !sendable.active?
      end

      # Send the email
      begin
        case email_type
        when "onboarding"
          UserMailer.product_onboarding_email(user, operator, template, sendable).deliver_now
        when "follow_up"
          UserMailer.product_follow_up_email(user, operator, template, sendable).deliver_now
        when "nudge"
          UserMailer.signup_nudge_email(user, operator, template).deliver_now
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
end

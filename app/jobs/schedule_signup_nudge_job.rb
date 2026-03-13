class ScheduleSignupNudgeJob < ApplicationJob
  queue_as :default

  def perform(user_id, operator_id)
    operator = Operator.find_by(id: operator_id)
    return unless operator

    ActsAsTenant.with_tenant(operator) do
      template = ProductEmailTemplate.find_by(
        operator: operator,
        product_type: "signup_nudge",
        email_type: "nudge"
      )
      return unless template&.enabled? && template.body.present?

      delay = (template.follow_up_delay_days || 1).days

      SendProductEmailJob.set(wait: delay).perform_later(
        "User",
        user_id,
        operator_id,
        "signup_nudge",
        "nudge",
        user_id
      )
    end
  end
end

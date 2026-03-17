class ScheduleSignupNudgeJob < ApplicationJob
  queue_as :default

  def perform(user_id, operator_id)
    operator = Operator.find_by(id: operator_id)
    return unless operator

    ActsAsTenant.with_tenant(operator) do
      user = User.find_by(id: user_id)
      return unless user

      location = Location.find_by(id: user.original_location_id)

      template = ProductEmailTemplate.find_by(
        operator: operator,
        location: location,
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

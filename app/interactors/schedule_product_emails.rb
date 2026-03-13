class ScheduleProductEmails
  include Interactor

  def call
    sendable = context.product_email_sendable
    product_type = context.product_email_type
    user = context.product_email_user
    operator = context.operator

    return unless sendable && product_type && user && operator

    # Schedule onboarding email (immediate)
    onboarding_template = ProductEmailTemplate.find_by(
      operator: operator,
      product_type: product_type,
      email_type: "onboarding"
    )

    if onboarding_template&.enabled?
      SendProductEmailJob.perform_later(
        sendable.class.name,
        sendable.id,
        operator.id,
        product_type,
        "onboarding",
        user.id
      )
    end

    # Schedule follow-up email (delayed)
    follow_up_template = ProductEmailTemplate.find_by(
      operator: operator,
      product_type: product_type,
      email_type: "follow_up"
    )

    if follow_up_template&.enabled?
      delay = (follow_up_template.follow_up_delay_days || 1).days
      SendProductEmailJob.set(wait: delay).perform_later(
        sendable.class.name,
        sendable.id,
        operator.id,
        product_type,
        "follow_up",
        user.id
      )
    end
  rescue => e
    # Don't fail the main transaction if email scheduling fails
    Honeybadger.notify(e)
    Rails.logger.error("ScheduleProductEmails failed: #{e.class}: #{e.message}")
  end
end

class Notifications::SubscriptionNotification
  include Interactor

  delegate :user, :subscription, :operator, to: :context

  def call
    message = "#{user.name} has subscribed to #{subscription.plan.pretty_name}"

    if !user.approved?
      message = "Approval required: #{message}"
    end

    result = Notifications::PushNotifier.call(
      message: message,
      operator: operator
    )

    if !result.success?
      Rollbar.error("Error pushing notification: #{result.message}")
    end
  end
end
class Notifications::DayPassNotification
  include Interactor

  delegate :user, :operator, to: :context

  def call
    message = "#{user.name} has purchased a day pass."
    
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
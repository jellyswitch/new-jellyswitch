class CreateOperatorJob < ApplicationJob
  queue_as :default

  def perform(operator, user)
    result = Demo::FinishCreatingOperator.call(operator: operator, user: user)
    if !result.success?
      Rollbar.error(result.message)
    end
  end
end

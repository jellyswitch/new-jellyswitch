class DestroyOperatorJob < ApplicationJob
  queue_as :default

  def perform(operator)
    result = Demo::DestroyOperator.call(operator: operator)
    if !result.success?
      Rollbar.error(result.message)
    end
  end
end

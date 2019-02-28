class CreateOperatorJob < ApplicationJob
  queue_as :default

  def perform
    result = Demo::CreateOperator.call
    if !result.success?
      Rollbar.error(result.message)
    end
  end
end

class Demo::DestroyOperator
  include Interactor

  def call
    operator = context.operator

    # Delete subdomain
    result = Demo::ReleaseSubdomain.call(operator: operator)
    if !result.success?
      context.fail!(message: "Error while destroy operator: #{result.message}")
    end

    # Delete operator
    if !operator.destroy
      context.fail!(message: "Unable to destroy operator")
    end
  end
end
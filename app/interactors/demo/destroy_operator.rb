class Demo::DestroyOperator
  include Interactor

  def call
    operator = context.operator

    # Delete subdomain
    result = Demo::ReleaseSubdomain.call(operator: operator)
    if !result.success?
      context.fail!(message: "Error while destroy operator: #{result.message}")
    end

    # Delete admins
    operator.users.admins.non_superadmins.destroy_all

    # Destroy plans
    operator.plans.destroy_all

    # Delete operator
    if !operator.destroy
      context.fail!(message: "Unable to destroy operator")
    end
  end
end
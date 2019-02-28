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

    # Destroy invoices
    operator.invoices.destroy_all

    # Destroy subscriptions
    operator.plans.each do |plan|
      plan.subscriptions.each do |subscription|
        subscription.active = false
        subscription.save!
      end
      plan.destroy
    end

    # Destroy members
    operator.users.members.destroy_all

    # Destroy day passes
    operator.day_pass_types.destroy_all

    # Delete operator
    if !operator.destroy
      context.fail!(message: "Unable to destroy operator")
    end
  end
end
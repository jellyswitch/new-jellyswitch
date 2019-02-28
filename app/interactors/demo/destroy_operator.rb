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
        if !subscription.destroy
          context.fail!(message: "Unable to cancel subscription.")
        end
      end
      plan.destroy
    end

    # Destroy day passes
    operator.day_pass_types.each do |day_pass_type|
      day_pass_type.day_passes.destroy_all
      day_pass_type.destroy
    end

    # Reservations
    operator.rooms.each do |room|
      room.reservations.destroy_all
      room.destroy
    end

    # Member Feedbacks
    operator.member_feedbacks.destroy_all

    # Destroy members
    operator.users.members.each do |member|
      member.stripe_customer.delete
      member.destroy
    end

    # Feed Items
    operator.feed_items.destroy_all

    # Doors
    operator.doors.destroy_all

    # Delete operator
    if !operator.destroy
      context.fail!(message: "Unable to destroy operator")
    end
  end
end
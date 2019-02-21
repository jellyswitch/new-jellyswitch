class CreateDayPass
  include Interactor
  include FeedItemCreator

  def call
    operator = context.operator
    user = User.find(context.user_id)
    if user.nil?
      context.fail!(message: "No such user with ID #{context.user_id}")
    end

    day_pass = DayPass.new(context.params)
    day_pass.user = user

    context.day_pass = day_pass
    
    result = UpdateUserPayment.call(
      user: user,
      token: context.token
    )
    
    if !result.success?
      context.fail!(message: "Unable to update payment method.")
    end

    if !day_pass.save
      context.fail!(message: "Unable to create day pass.")
    end

    charge = Stripe::Charge.create({
      amount: operator.day_pass_cost_in_cents,
      currency: 'usd',
      description: day_pass.charge_description,
      customer: user.stripe_customer_id
    })

    day_pass.stripe_charge_id = charge.id
    if !day_pass.save
      context.fail!(message: "There was a problem charging this day pass.")
    end

    blob = {type: "day-pass", day_pass_id: day_pass.id}
    create_feed_item(user.operator, user, blob)

  rescue Exception => e
    context.fail!(message: e.message)
  end
end
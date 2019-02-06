class CreateDayPass
  include Interactor

  def call
    user = User.find(context.user_id)
    if user.nil?
      context.fail!(message: "No such user with ID #{context.user_id}")
    end

    day_pass = DayPass.new(context.params)
    day_pass.user = user

    context.day_pass = day_pass
    
    user.ensure_stripe_customer(context.token)

    if !day_pass.save
      context.fail!(message: "Unable to create day pass.")
    end

    feed_item = FeedItem.new
    feed_item.operator = user.operator
    feed_item.user = user
    feed_item.blob = {type: "day-pass", day_pass_id: day_pass.id}
    if !feed_item.save
      context.fail!(message: "Unable to generate feed item.")
    end
  rescue Exception => e
    context.fail!(message: e.message)
  end
end
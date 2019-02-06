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
  rescue Exception => e
    context.fail!(message: e.message)
  end
end
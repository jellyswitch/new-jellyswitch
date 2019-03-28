class CreateUser
  include Interactor
  include FeedItemCreator

  def call
    @user = User.new(context.params)

    if !context.operator.approval_required
      @user.approved = true
    end

    @user.operator = context.operator
    
    if !@user.save
      context.fail!(message: "Unable to create user.")
    end

    blob = {type: "new-user"}
    create_feed_item(@user.operator, @user, blob)

    result = CreateStripeCustomer.call(user: @user)
    
    if !result.success?
      context.fail!(message: result.message)
    end

    context.user = @user
  rescue Exception => e
    Rollbar.error("Interactor Failure (#{self.class.name}): #{e.inspect} #{e.message}")
    context.user = @user
    context.fail!(message: e.)
  end
end
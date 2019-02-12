class CreateUser
  include Interactor

  def call
    @user = User.new(context.params)

    if !context.operator.approval_required
      @user.approved = true
    end

    @user.operator = context.operator
    
    if !@user.save
      context.fail!(message: "Unable to create user.")
    end

    feed_item = FeedItem.new
    feed_item.operator = @user.operator
    feed_item.user = @user
    feed_item.blob = {type: "new-user"}

    if !feed_item.save
      context.fail!(message: "Unable to generate feed item.")
    end

    result = CreateStripeCustomer.call(user: @user)
    
    if !result.success?
      context.fail!(message: result.message)
    end

    context.user = @user
  rescue Exception => e
    context.user = @user
    context.fail!(message: e.message)
  end
end
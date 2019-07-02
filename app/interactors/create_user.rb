# typed: true
class CreateUser
  include Interactor
  include FeedItemCreator

  def call
    @user = User.new(context.params)
    context.user = @user

    if !context.operator.approval_required
      @user.approved = true
    end

    @user.operator = context.operator

    if !@user.save
      context.fail!(message: "Unable to sign up. Please see below for errors.")
    end

    blob = { type: "new-user" }
    create_feed_item(@user.operator, @user, blob)

    result = CreateStripeCustomer.call(user: @user)

    if !result.success?
      context.fail!(message: result.message)
    end
  end
end

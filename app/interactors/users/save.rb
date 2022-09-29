
class Users::Save
  include Interactor
  include FeedItemCreator
  include ErrorsHelper

  def call
    @user = User.new(context.params)
    context.user = @user

    if !context.operator.approval_required
      @user.approved = true
    end

    @user.operator = context.operator

    if !@user.save
      context.fail!(message: "Unable to sign up. Please review errors. #{errors_for(@user)}")
    end

    context.notifiable = @user
   
    result = CreateStripeCustomer.call(user: @user)

    if !result.success?
      context.fail!(message: result.message)
    end
  end
end

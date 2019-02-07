class CreateUser
  include Interactor

  def call
    # OLD
    @user = User.new(context.params)

    if !context.operator.approval_required
      @user.approved = true
    end
    @user.operator = context.operator
    
    if !@user.save
      context.fail!(message: "Unable to create user.")
    end

    context.user = @user
  rescue Exception => e
    context.user = @user
    context.fail!(message: e.message)
  end
end
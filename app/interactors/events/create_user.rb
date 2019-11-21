class Events::CreateUser
  include Interactor

  delegate :event, :email, to: :context

  def call
    result = ::CreateUser.call(
      params: {
        name: email,
        email: email,
        password: "pizza123",
        password_confirmation: "pizza123"

      },
      operator: event.location.operator
    )

    if !result.success?
      context.fail!(message: result.message)
    end

    context.user = result.user

    result = Events::SetPasswordAndSendEmail.call(user: result.user, event: event)

    if !result.success?
      context.fail!(message: result.message)
    end
  end
end
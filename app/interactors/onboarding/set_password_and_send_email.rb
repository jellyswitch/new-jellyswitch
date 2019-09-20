class Onboarding::SetPasswordAndSendEmail
  include Interactor

  delegate :user, to: :context

  def call
    context.password = Faker::Science.element
    unless user.update(password: context.password)
      context.fail!(message: "Unable to update password.")
    end

    UserMailer.onboarding(user, context.password).deliver_later
  end
end
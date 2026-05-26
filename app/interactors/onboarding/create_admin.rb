class Onboarding::CreateAdmin
  include Interactor
  include ErrorsHelper

  delegate :email, :password, :password_confirmation, :operator, to: :context

  def call
    # Refuse to proceed without a password. The previous behavior — hardcoded
    # `password: "foobar"` — meant every workspace owner had the same known
    # password until they happened to change it, which is an account-takeover
    # vector for any operator-onboarding account that's still using it.
    if password.blank?
      context.fail!(message: "Password is required.")
      return
    end

    user = User.new(
      name: email,
      email: email,
      password: password,
      password_confirmation: password_confirmation,
      admin: true,
      operator_id: operator.id,
      admin_created: true,
    )

    if user.save
      user.profile_photo.attach(io: image = File.open(Rails.root.join("app/assets/images/avatars/1.jpg")), filename: "1.jpg")
      context.user = user
    else
      context.fail!(message: "CreateAdmin: #{ errors_for(user) }")
    end
  end

  def rollback
    context.user.destroy
  end
end
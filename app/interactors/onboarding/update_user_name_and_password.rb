class Onboarding::UpdateUserNameAndPassword
  include Interactor
  include ErrorsHelper

  delegate :user, :name, :password, to: :context

  def call
    user.name = name
    user.password = password

    unless user.save
      context.fail!(errors_for(user))
    end
  end
end
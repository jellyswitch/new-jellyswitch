class Onboarding::UpdateOperatorName
  include Interactor
  include ErrorsHelper

  delegate :user, :operator_name, to: :context

  def call
    operator = user.operator
    operator.name = operator_name

    unless operator.save
      context.fail!(message: errors_for(operator))
    end
  end
end
class Onboarding::UpdateOperatorName
  include Interactor
  include ErrorsHelper

  delegate :user, :operator_name, to: :context

  def call
    operator = user.operator
    operator.name = operator_name
    chosen = context.subdomain.presence || operator_name
    operator.subdomain = chosen.parameterize
    context.operator = operator
    unless operator.save
      context.fail!(message: errors_for(operator))
    end
  end
end
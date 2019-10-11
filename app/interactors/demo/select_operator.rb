class Demo::SelectOperator
  include Interactor

  delegate :subdomain, to: :context

  def call
    operator = Operator.find_by(subdomain: subdomain)

    if operator
      context.operator = operator
    else
      context.fail!(message: "Could not find operator with subdomain: #{subdomain}.")
    end
  end
end
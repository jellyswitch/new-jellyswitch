class Demo::Clean::Plans
  include Interactor

  delegate :operator, to: :context

  def call
    operator.plans.each do |plan|
      plan.delete
    end
  end
end
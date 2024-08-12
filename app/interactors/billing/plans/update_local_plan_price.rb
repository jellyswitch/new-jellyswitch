class Billing::Plans::UpdateLocalPlanPrice
  include Interactor

  delegate :office_lease, :new_price_in_cents, to: :context

  def call
    plan = office_lease.subscription.plan

    if plan.update(amount_in_cents: new_price_in_cents)
      context.plan = plan
    else
      context.fail!(message: "Couldn't update plan price.")
    end
  end
end

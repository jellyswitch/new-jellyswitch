class Demo::CreatePlans
  include Interactor

  def call
    operator = context.operator

    Plan.create!(
      name: "Part Time Membership",
      interval: "monthly",
      amount_in_cents: 15000,
      visible: true,
      available: true,
      operator_id: operator.id
    )

    Plan.create!(
      name: "Full Time Membership",
      interval: "monthly",
      amount_in_cents: 40000,
      visible: true,
      available: true,
      operator_id: operator.id
    )

    Plan.create!(
      name: "Private Office (Small)",
      interval: "monthly",
      amount_in_cents: 60000,
      visible: true,
      available: true,
      operator_id: operator.id
    )

    Plan.create!(
      name: "Private Office (Large)",
      interval: "monthly",
      amount_in_cents: 120000,
      visible: true,
      available: true,
      operator_id: operator.id
    )
  rescue Exception => e
    context.fail!(message: "Couldn't create plans: #{e.message}")
  end
end
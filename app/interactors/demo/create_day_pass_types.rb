class Demo::CreateDayPassTypes
  include Interactor

  def call
    operator = context.operator

    DayPassType.create!(
      name: "Standard Day Pass",
      amount_in_cents: 3500,
      available: true,
      visible: true,
      operator_id: operator.id
    )

    DayPassType.create!(
      name: "Discounted Day Pass",
      amount_in_cents: 2000,
      available: true,
      visible: false,
      operator_id: operator.id
    )
  end
end
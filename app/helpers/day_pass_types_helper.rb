module DayPassTypesHelper
  def day_pass_type_options(day_pass_types)
    day_pass_types.map do |day_pass_type|
      [
        "#{day_pass_type.name} (#{number_to_currency(day_pass_type.amount_in_cents.to_f / 100.00)})",
        day_pass_type.id,
      ]
    end
  end
end

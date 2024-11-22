
class Billing::DayPasses::RedeemCode
  include Interactor

  delegate :code, :operator, :location, to: :context

  def call
    day_pass_types = DayPassType.for_location(location).for_code(code)
    case day_pass_types.count
    when 0
      context.fail!(message: "We couldn't find a day pass for that code. Is the code for a different location? Please check and try again.")
    else
      context.day_pass_type = day_pass_types.first
    end
  end
end
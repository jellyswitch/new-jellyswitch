class Billing::Reservations::ChargeCredits
  include Interactor
  include CreditHelper

  delegate :reservation_params, :user, to: :context

  def call
    @existing_balance = user.credit_balance

    @charge_amount = reservation_cost(reservation_params[:room], reservation_params[:minutes])

    if user.credit_balance < @charge_amount
      context.fail!(message: "Insufficient credit balance.")
    end

    if !user.update(credit_balance: ending_balance(user, @charge_amount))
      context.fail!(message: "Unable to set user credit balance.")
    end
  end

  def rollback
    user.update(credit_balance: @existing_balance)
  end
end
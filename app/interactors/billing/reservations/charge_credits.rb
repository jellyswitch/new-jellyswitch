class Billing::Reservations::ChargeCredits
  include Interactor
  include CreditHelper

  delegate :reservation, :reservation_params, :user, to: :context

  def call
    if user.operator.credits_enabled?
      if !staff?
        @existing_balance = user.credit_balance

        room = reservation.room || reservation_params[:room]
        minutes = reservation.minutes || reservation_params[:minutes]

        @charge_amount = reservation_cost(room, minutes)

        if user.credit_balance < @charge_amount
          context.fail!(message: "Insufficient credit balance.")
        end

        if !user.update(credit_balance: ending_balance(user, @charge_amount))
          context.fail!(message: "Unable to set user credit balance.")
        end

        if !reservation.update(credit_cost: @charge_amount)
          context.fail!(message: "Unable to record credit cost on reservation.")
        end
      end
    end
  end

  def rollback
    if user.operator.credits_enabled?
      if !staff?
        user.update(credit_balance: @existing_balance)
        reservation.update(credit_cost: 0)
      end
    end
  end

  def staff?
    user.admin? || user.general_manager? || user.community_manager?
  end
end

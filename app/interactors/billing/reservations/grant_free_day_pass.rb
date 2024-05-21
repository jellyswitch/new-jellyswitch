class Billing::Reservations::GrantFreeDayPass
  include Interactor

  def call
    user = context.user
    reservation = context.reservation
    location = reservation.room.location
    reservation_day = reservation.datetime_in.to_date

    if reservation.room.paid_room? && user.should_charge_for_reservation?(location, reservation_day)
      free_day_passes = DayPassType.for_operator(location.operator).free.available
      if free_day_passes.count > 0
        free_day_pass_type = free_day_passes.first
        invoice = Invoice.find_by(stripe_invoice_id: context.invoice&.id)

        day_pass = DayPass.new(user: user, day: reservation_day, day_pass_type: free_day_pass_type, operator: location.operator, billable_type: "User", billable_id: user.id, invoice: invoice)
        if day_pass.save
          Rails.logger.info "Granted a free day pass to #{user.email} for reservation #{reservation.id}"
        else
          context.fail!(message: "Failed to grant a free day pass to #{user.email} for reservation #{reservation.id}: #{day_pass.errors.full_messages.join(", ")}")
        end
      else
        context.fail!(message: "Failed to find a free day pass type for reservation #{reservation.id}")
      end
    end
  end
end

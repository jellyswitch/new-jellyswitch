module RecurringReservations
  class CancelSeries
    include Interactor

    def call
      recurring = context.recurring_reservation

      ActiveRecord::Base.transaction do
        recurring.update!(cancelled: true)
        recurring.reservations.future.update_all(cancelled: true)
      end

      context.cancelled_count = recurring.reservations.where(cancelled: true).count
    rescue ActiveRecord::RecordInvalid => e
      context.fail!(message: e.message)
    end
  end
end

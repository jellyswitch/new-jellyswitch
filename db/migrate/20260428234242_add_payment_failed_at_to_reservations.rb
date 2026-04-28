class AddPaymentFailedAtToReservations < ActiveRecord::Migration[7.1]
  def change
    # Set when an authorize-hold or capture step fails on a reservation
    # (card declined, hold expired by Stripe, etc.). Surfaces in the
    # admin feed as a "payment_failed_room_reservation" item and gates
    # the reservation as needing operator attention. Distinct from
    # `cancelled` — the booking still exists, it just isn't paid.
    add_column :reservations, :payment_failed_at, :datetime
  end
end

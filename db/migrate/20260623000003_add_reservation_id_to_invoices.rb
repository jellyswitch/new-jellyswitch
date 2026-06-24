class AddReservationIdToInvoices < ActiveRecord::Migration[7.2]
  # Phase 2 of the reservation billing redesign (ADR 0010/0011): a reservation
  # can carry several invoices (the booking capture + any extension deltas), so
  # a cancel must refund ALL of them. A nullable reservation_id links each
  # invoice back to its reservation; it's stamped at booking and on every
  # extension. Additive + reversible. Index built CONCURRENTLY since `invoices`
  # is large in prod and a plain index would lock writes.
  disable_ddl_transaction!

  def change
    add_column :invoices, :reservation_id, :bigint
    add_index :invoices, :reservation_id, algorithm: :concurrently
  end
end

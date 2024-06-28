namespace :reservations do
  desc "Update paid status for future reservations"
  task update_paid_status: :environment do
    start_date = Time.zone.today
    updated_ids = []

    Reservation.unscoped.where("datetime_in >= ?", start_date).find_each do |reservation|
      paid_status = reservation.is_charged?

      reservation.update_column(:paid, paid_status)
      updated_ids << reservation.id
    end

    puts "Task completed. Updated #{updated_ids.size} future reservations."
    puts "Updated reservation IDs: #{updated_ids.join(", ")}"
  end
end

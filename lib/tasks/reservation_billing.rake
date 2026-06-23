namespace :reservation_billing do
  # Phase 1 (ADR 0012) removed GrantFreeDayPass: paid-room bookings no longer
  # mint a complimentary DayPass. But comp passes minted BEFORE this deploy can
  # still poison a same-day edit/room-switch (their included_meeting_room_minutes
  # re-price through the day-pass overage branch — the "Brad bug") until they age
  # out at day rollover. This purges the still-active ones.
  #
  # Target = the exact GrantFreeDayPass signature, intersected with its trigger:
  #   - complimentary: true              (it set complimentary: true)
  #   - billable_type: "User"            (it set billable_type "User")
  #   - day_pass_type is FREE            (it used DayPassType.free, amount 0)
  #   - day >= today                     (past passes already aged out)
  #   - the user has a non-cancelled reservation on a PAID room that same day
  #     (GrantFreeDayPass only fired for reservation.room.paid_room?)
  #
  # The same-day paid-reservation correlation is what keeps this from deleting
  # comp passes granted for any other reason (admin comps, new-user free passes).
  #
  # Dry-run by default. Run for real with COMMIT=1:
  #   bin/rails reservation_billing:purge_comp_passes            # preview
  #   COMMIT=1 bin/rails reservation_billing:purge_comp_passes   # destroy
  desc "Purge active comp DayPasses minted by the removed GrantFreeDayPass (dry-run unless COMMIT=1)"
  task purge_comp_passes: :environment do
    commit = ENV["COMMIT"] == "1"

    candidates = DayPass.complimentary
                        .where(billable_type: "User")
                        .where("day >= ?", Date.current)
                        .joins(:day_pass_type)
                        .where(day_pass_types: { amount_in_cents: 0 })

    to_destroy = []
    candidates.find_each do |dp|
      paid_reservation = Reservation.joins(:room)
                                    .where(user_id: dp.user_id, cancelled: false)
                                    .where(datetime_in: dp.day.beginning_of_day..dp.day.end_of_day)
                                    .where("rooms.hourly_rate_in_cents > 0")
                                    .first
      next unless paid_reservation

      to_destroy << dp
      puts "  DayPass ##{dp.id} | user #{dp.user&.email} | day #{dp.day} | " \
           "type '#{dp.day_pass_type&.name}' | paid reservation ##{paid_reservation.id} " \
           "(#{paid_reservation.room&.name})"
    end

    puts "\n#{to_destroy.size} comp day pass(es) match the GrantFreeDayPass signature."

    if to_destroy.empty?
      puts "Nothing to purge."
    elsif commit
      ids = to_destroy.map(&:id)
      DayPass.where(id: ids).destroy_all
      puts "Destroyed #{ids.size} comp day pass(es): #{ids.join(', ')}"
    else
      puts "DRY RUN — nothing destroyed. Re-run with COMMIT=1 to destroy."
    end
  end
end

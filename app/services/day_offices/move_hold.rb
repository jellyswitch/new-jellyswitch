# Atomic date-move for a Day Office pass (Task 9, ADR 0026): release the old
# hold, move the pass, allocate on the target date — all in one transaction,
# so a full target date rolls everything back (the old hold's release
# included) and nothing changes.
#
# Release-FIRST is load-bearing: Allocator.allocate!'s idempotency guard
# returns any LIVE hold for the pass, so allocating before releasing would
# just hand back the old-date hold and silently not move it.
module DayOffices
  class MoveHold
    Result = Struct.new(:ok?, :hold)

    def self.call(day_pass:, new_day:)
      moved = nil
      # uncached: same stale-read footgun Allocator closes — reload_office_hold must always hit the DB.
      ActiveRecord::Base.uncached do
        DayPass.transaction do
          ReleaseHold.call(day_pass.reload_office_hold)
          day_pass.update!(day: new_day)
          moved = Allocator.allocate!(day_pass: day_pass)
          raise ActiveRecord::Rollback if moved.nil?
        end
      end
      moved ? Result.new(true, moved) : Result.new(false, nil)
    end
  end
end

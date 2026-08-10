# Admin-only narrow move (ADR 0026 decision #8): any active room at the
# hold's location — hidden included — that is free for the hold's exact
# window. Notifies the member (push + email) after the write commits.
#
# hold.update! is a single autocommit statement (no surrounding transaction),
# so Notify firing right after it is already safely "after commit" — see
# DayOffices::Notify's header for why an enqueue must never precede one.
#
# Liveness guard, first, before anything else: a hold that's already
# released (member/admin cancelled it, a refund rescinded the pass) or whose
# window has already ended is not a live thing to move. Both admin surfaces
# can still FIND a cancelled/ended hold by id (the API finder is
# .unscoped, and the operator controller's is too — see reassign_room
# there) specifically so this guard is what answers, with a clear refusal,
# instead of a bare 404 that looks identical to "wrong id". An ONGOING hold
# (started, not yet ended) is still live and must reassign normally — only
# datetime_OUT is checked.
#
# capacity-0 target: hold.update! re-runs Reservation's own validations,
# including attendee_count_within_capacity. A pool room whose capacity got
# edited down to 0 after being added to the pool (same drift Allocator guards
# against) would otherwise blow this call up with an unhandled RecordInvalid.
# There is no "sold out" fallback to hand back here (unlike Allocator), so the
# correct behavior is to refuse outright with a readable message instead of
# raising — the rescue below is scoped tightly around just the update! call so
# a real bug elsewhere in Reservation validation still surfaces as a genuine
# error, and Notify never fires on a failed write.
module DayOffices
  class ReassignRoom
    # moved?: false for the same-room no-op (nothing actually happened), true
    # after a real move. Callers use it to pick between "moved" and "already
    # there" copy without re-deriving it from old/new room ids themselves.
    Result = Struct.new(:ok?, :error, :moved?)

    def self.call(hold:, room:)
      if hold.nil? || hold.cancelled? || hold.datetime_out <= Time.current
        return Result.new(false, "That office hold is no longer active.")
      end
      return Result.new(false, "Not a Day Office hold.") unless hold.day_office_hold?
      return Result.new(false, "Room not found at this location.") if room.nil? ||
        room.location_id != hold.room.location_id || room.archived?

      old_room = hold.room
      return Result.new(true, nil, false) if room.id == old_room.id

      # uncached: same stale-read footgun Allocator/MoveHold close — without
      # it, an earlier read in this same request (e.g. the options-listing
      # probe that likely just ran) can leave a "free" result sitting in
      # Rails' per-request SQL query cache, so this probe reads that cache
      # instead of the DB and misses a room another admin/member just took.
      taken = ActiveRecord::Base.uncached do
        Reservation.overlapping(hold.datetime_in, hold.datetime_out)
                   .where(room_id: room.id).where.not(id: hold.id).exists?
      end
      return Result.new(false, "#{room.name} is already booked then.") if taken

      begin
        hold.update!(room: room)
      rescue ActiveRecord::RecordInvalid => e
        return Result.new(false, e.record.errors.full_messages.to_sentence)
      end

      DayOffices::Notify.reassigned(hold: hold, old_room_name: old_room.name)
      Result.new(true, nil, true)
    end
  end
end

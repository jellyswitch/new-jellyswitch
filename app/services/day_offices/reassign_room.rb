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

    # The reassign picker's candidate list (Task 14): any ACTIVE room at the
    # hold's location — hidden included, same decision #8 as .call above —
    # other than the hold's current room, that is free for the hold's exact
    # window. Shared by the admin API's reassign_options action and the web
    # profile's inline Reassign select so the two surfaces can never drift.
    #
    # Two queries total, not one exists? per candidate: pluck every occupied
    # room id for the hold's window in a single query, then reject in Ruby
    # against a Set (O(1) membership) instead of round-tripping per room.
    #
    # No liveness guard here (unlike .call) — callers that need "is this hold
    # still live" (a cancelled/ended hold shouldn't be offered a move at all)
    # check that themselves before calling, same as reassign_options already
    # does. This method only answers "what rooms are free", nothing about
    # whether the hold itself is still eligible to move.
    #
    # Room.unscoped: Room's own acts_as_scopable(:operator, :location) default
    # scope — populated for the whole request by
    # Operator::BaseController#set_resource_scopes when this is called from
    # the web profile — would otherwise silently AND the admin's OWN
    # current_location into the candidate query below. For a hold at a
    # DIFFERENT location (the web profile lists every hold for a member
    # across all locations), that combined condition can never match
    # anything, so every room reads as unavailable instead of merely the ones
    # actually taken. The admin API (this method's original call site) never
    # sets that ambient scope, so this is a no-op there — mirrors
    # Reservation#room's own Room.unscoped { super } override, same reason.
    def self.options_for(hold)
      Room.unscoped do
        candidates = Room.active.where(location_id: hold.room.location_id)
                         .where.not(id: hold.room_id).order(:name).to_a

        # uncached: same stale-read footgun .call's own occupancy probe closes
        # — without it a query cached earlier in this request/test could hand
        # back a "free" room another admin/member just took.
        ActiveRecord::Base.uncached do
          occupied_ids = Reservation.overlapping(hold.datetime_in, hold.datetime_out)
                                    .where(room_id: candidates.map(&:id)).where.not(id: hold.id)
                                    .distinct.pluck(:room_id).to_set
          candidates.reject { |r| occupied_ids.include?(r.id) }
        end
      end
    end

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

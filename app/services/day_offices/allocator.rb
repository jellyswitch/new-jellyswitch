# Assigns a pool room to a Day Office pass (ADR 0026). Same-type allocation is
# serialized by taking FOR UPDATE on the pool's join rows in a transaction, so
# two allocate! calls for the SAME day_pass_type never race each other.
# Cross-type and hourly-booking overlaps carry no DB constraint and remain a
# TOCTOU window between this method's read and its Reservation#create! write —
# accepted, consistent with the rest of the codebase's existing booking-race
# posture (see ReservationValidator). The validator narrows that window (a
# losing create! raises RecordInvalid tagged :overlap, which allocate! turns
# into a nil/"sold out" result) but does not close it.
module DayOffices
  class Allocator
    def self.available_room(day_pass_type:, day:, exclude_reservation_id: nil, span: nil)
      span ||= day_pass_type.location&.posted_hours_span(day)
      return nil if span.nil?

      # uncached: allocate! re-probes this AFTER acquiring the pool lock, to see
      # any reservation a concurrent request committed while we waited for the
      # lock. Without this, an earlier read in the SAME request (e.g. a
      # pre-check gate) can leave a stale "room free" result sitting in Rails'
      # per-request SQL query cache, so the re-probe reads that cache instead of
      # the DB, picks an already-taken room, and create! below rejects it —
      # reporting a false "sold out" even though another pool room is free.
      ActiveRecord::Base.uncached do
        day_pass_type.office_rooms.merge(Room.active).detect do |room|
          scope = Reservation.overlapping(span.first, span.last).where(room_id: room.id)
          scope = scope.where.not(id: exclude_reservation_id) if exclude_reservation_id
          !scope.exists?
        end
      end
    end

    # Returns the created hold Reservation, or nil when no room is free.
    def self.allocate!(day_pass:)
      type = day_pass.day_pass_type
      span = type.location&.posted_hours_span(day_pass.day)
      return nil if span.nil?

      # uncached wraps the WHOLE transaction, not just available_room's own
      # internal probe: the idempotency find_by below runs the same SQL a
      # has_one :office_hold (T6) would run for an earlier read in this same
      # request (e.g. a serializer touching day_pass.office_hold before this
      # method is called) — that read can seed the per-request query cache, so
      # without this every read taken after the pool lock, not just
      # available_room's, is fresh as a property of this method, not something
      # each caller has to remember to arrange.
      ActiveRecord::Base.uncached do
        Reservation.transaction do
          type.day_pass_type_rooms.lock(true).to_a # serialize same-SKU allocation

          # Idempotent: a retried request (e.g. a client timeout-and-retry on an
          # allocation that actually succeeded) must not double-book a second room.
          existing = Reservation.find_by(day_office_pass_id: day_pass.id)
          next existing if existing

          room = available_room(day_pass_type: type, day: day_pass.day, span: span)
          next nil if room.nil?

          Reservation.create!(
            user: day_pass.user, room: room,
            datetime_in: span.first, minutes: ((span.last - span.first) / 60).round,
            paid: false, attendee_count: 1, day_office_pass_id: day_pass.id
          )
        rescue ActiveRecord::RecordInvalid => e
          # Only a genuine overlap loss is "sold out." Anything else (e.g. a pool
          # room whose capacity was dropped to 0 after assignment, failing
          # attendee_count_within_capacity) is a real config error and must
          # surface, not be silently misreported as no-office-free forever.
          raise unless e.record.errors.of_kind?(:base, :overlap)
          nil # lost a cross-type race; caller treats as no office free
        end
      end
    end
  end
end

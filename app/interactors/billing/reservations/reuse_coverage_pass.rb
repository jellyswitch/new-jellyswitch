# Re-date a member's leftover purchased pass (from a cancelled booking) onto
# this reservation's date instead of charging again (ADR 0019). Guarded by the
# client's `use_existing_pass` decision. The pass keeps its invoice + type, so
# the paid purchase and its included-minutes/overage carry over. Runs before
# ChargeAtBooking so the pass zeroes the base charge.
class Billing::Reservations::ReuseCoveragePass
  include Interactor

  delegate :reservation, :user, :use_existing_pass, :coverage_pass, to: :context

  def call
    return unless use_existing_pass
    return unless reservation&.persisted?

    pass = coverage_pass || pick_spare
    return unless pass

    @previous_day = pass.day
    @previous_reservation_id = pass.reservation_id
    pass.update!(day: reservation.datetime_in.to_date, reservation: reservation)
    context.coverage_pass = pass
    context.outcome = :reused
  end

  # Undo the re-date if a later organizer step fails.
  def rollback
    pass = context.coverage_pass
    return unless pass && @previous_day
    pass.update!(day: @previous_day, reservation_id: @previous_reservation_id)
  rescue => e
    Rails.logger.error("ReuseCoveragePass rollback failed for reservation #{reservation&.id}: #{e.class}: #{e.message}")
  end

  private

  def pick_spare
    today = ActiveSupport::TimeZone[reservation.room.location.time_zone.presence || "UTC"].today
    user.day_passes.reusable_coverage(today).where(location: reservation.room.location)
        .where.not(day: reservation.datetime_in.to_date).order(:day).first
  end
end

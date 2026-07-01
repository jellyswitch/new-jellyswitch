# Buy day-pass coverage for an included-room booking's date instead of the
# controller's old silent auto-buy (ADR 0019). Guarded by the client's
# `buy_day_pass` decision. Reuses Billing::DayPasses::CreateDayPass (which
# charges via ChargeDayPassInvoice), then stamps the reservation link so the
# purchased pass survives a later cancel and becomes reusable. Runs before
# ChargeAtBooking so the pass zeroes the base room charge.
class Billing::Reservations::BuyCoverageDayPass
  include Interactor

  delegate :reservation, :user, :buy_day_pass, :day_pass_type, :location, to: :context

  def call
    return unless buy_day_pass
    return unless reservation&.persisted?

    date = reservation.datetime_in.to_date
    type = day_pass_type || suggested_type
    context.fail!(message: "You need a day pass to book that date, but none is available.") unless type

    result = Billing::DayPasses::CreateDayPass.call(
      params: { day: date, day_pass_type: type.id, operator: location.operator },
      operator: location.operator, location: location, user_id: user.id, out_of_band: user.out_of_band?,
    )
    context.fail!(message: "Couldn't purchase day pass: #{result.message}") unless result.success?

    pass = user.day_passes.for_location(location).for_day(date).order(created_at: :desc).first
    pass&.update!(reservation: reservation)
    context.coverage_pass = pass
    context.outcome = :bought
  end

  # If a later organizer step fails, refund/void the just-bought pass so a
  # never-committed booking doesn't strand a paid pass. Reuses the same
  # refund primitive as invoice cancellation (Refundable::RefundableInvoice /
  # RefundableFactory) rather than destroying paid money silently.
  def rollback
    pass = context.coverage_pass
    return unless pass && context.outcome == :bought

    if pass.invoice.present?
      RefundableFactory.for(pass.invoice).cancel
    end
    pass.destroy
  rescue => e
    Rails.logger.error("BuyCoverageDayPass rollback failed for reservation #{reservation&.id}: #{e.class}: #{e.message}")
    Honeybadger.notify(e) rescue nil
  end

  private

  def suggested_type
    Billing::Reservations::CoverageState.for(
      user: user, room: reservation.room, date: reservation.datetime_in.to_date, location: location
    ).day_pass_type
  end
end

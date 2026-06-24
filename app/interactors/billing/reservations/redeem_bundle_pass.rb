class Billing::Reservations::RedeemBundlePass
  include Interactor

  # Opt-in reserve-time bundle redemption (ADR 0015). When the booker chose
  # "use 1 pass for today", spend one prepaid day-pass-bundle pass to cover a $0
  # (call) room: mint a DayPass for the reservation's date (the same artifact
  # ConsumeOnEntry mints on door entry) and burn one pass. The minted DayPass is
  # what makes ChargeCalculator return 0 (so ChargeAtBooking no-ops) and grants
  # access — pricing/permissions recognize bundles only via a DayPass.
  #
  # Runs after SaveRoomReservation (validated, persisted reservation) and before
  # ChargeAtBooking (so the minted pass zeroes the charge). One pass per
  # business-day period: deduped on "a DayPass for that location+date already
  # exists" — which also reconciles with the door (ConsumeOnEntry Guard 4 short-
  # circuits on this minted pass before its own burn), so the door never
  # double-burns and this needs no change to the door dedupe. Paid rooms are
  # never covered. No demo gate needed — a prepaid pass is state-agnostic, and
  # the pricing path already moves no money in demo.

  delegate :reservation, :user, :use_bundle_pass, to: :context

  def call
    return unless use_bundle_pass
    return unless reservation&.persisted?

    room = reservation.room
    return if room.hourly_rate_in_cents.to_i > 0 # paid rooms aren't covered by passes

    location = room.location
    day = reservation.datetime_in.to_date
    # Already covered for that day (a purchased pass, a prior reservation burn, or
    # a door entry) → don't burn a second pass.
    return if user.day_passes.for_location(location).for_day(day).exists?

    bundle = user.day_pass_bundles.active.where(location: location).first
    return unless bundle # no bundle / out of passes → fall through to normal pricing

    bundle.with_lock do
      # Re-check under the lock in case coverage landed concurrently.
      next if user.day_passes.for_location(location).for_day(day).exists?

      day_pass = DayPass.create!(
        user:          user,
        billable:      user,
        operator:      bundle.operator,
        location:      location,
        day_pass_type: bundle.day_pass_type,
        day:           day,
        imported:      true,
      )
      bundle.burn_locked!(kind: "reservation", performed_by: user, day_pass: day_pass, reservation: reservation)

      context.redeemed_bundle = bundle
      context.bundle_redemption_day_pass = day_pass
      context.outcome = :redeemed
    end
  rescue DayPassBundle::NoPassesRemaining
    # Emptied between the active-bundle check and the locked burn — leave it to
    # the pricing path (the booker simply isn't covered by a pass this time).
    Rails.logger.info("RedeemBundlePass: bundle emptied for reservation #{reservation&.id}; falling through to pricing")
  end

  # If a later organizer step fails, undo the burn so a never-committed booking
  # doesn't silently spend a pass. Direct reversal (not restore!) — no
  # admin_restore audit row for a booking that never happened.
  def rollback
    bundle = context.redeemed_bundle
    day_pass = context.bundle_redemption_day_pass
    return unless bundle && day_pass

    bundle.with_lock do
      bundle.redemptions.where(day_pass_id: day_pass.id, kind: "reservation").destroy_all
      day_pass.destroy
      bundle.update!(passes_remaining: bundle.passes_remaining + 1)
    end
  rescue => e
    Rails.logger.error("RedeemBundlePass rollback failed for reservation #{reservation&.id}: #{e.class}: #{e.message}")
    Honeybadger.notify(e) rescue nil
  end
end

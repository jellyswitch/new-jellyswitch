class Billing::DayPassBundles::ScheduleDay
  include Interactor

  HORIZON_DAYS = 90

  delegate :user, :location, :performed_by, to: :context

  def call
    tz    = ActiveSupport::TimeZone[location&.time_zone.presence || "UTC"]
    today = Time.current.in_time_zone(tz).to_date

    # m2: guard against unparseable date strings before any DB work.
    date = begin
      context.date.is_a?(String) ? Date.parse(context.date) : context.date
    rescue Date::Error, ArgumentError
      context.outcome = :invalid_date
      return
    end

    # m1: Integer + Integer (no .days) — Date arithmetic, not Duration.
    if date < today || date > today + HORIZON_DAYS
      context.outcome = :invalid_date
      return
    end

    # T10/ADR 0026: a Day Office bundle's coverage guard must not count a
    # subscription/lease/reservation as "covered" — the office IS the point
    # of scheduling, so those must not suppress the mint; only an existing
    # same-date pass blocks. Looking the bundle up here too (a second cheap,
    # indexed query) just to read its kind keeps the outcome for a COVERED,
    # BUNDLE-LESS user unchanged (:already_covered, not :no_bundle) — the
    # `bundle =` lookup right below is untouched and still owns :no_bundle.
    if already_covered?(date, tz, office: eligible_bundle(date, tz)&.day_pass_type&.day_office?)
      context.outcome = :already_covered
      return
    end

    # eligible_bundle runs BEFORE the lock. Under the single-active-bundle
    # assumption this is safe; a concurrent exhaust between here and with_lock
    # falls through to NoPassesRemaining → :no_bundle (accepted limitation).
    bundle = eligible_bundle(date, tz)
    unless bundle
      context.outcome = :no_bundle
      return
    end

    # Daily cap (opt-in). Only member self-serve scheduling enforces the cap —
    # the staff burn-for-customer path (Api::V1::Admin::MembersController#
    # schedule_bundle_days) shares this interactor and must stay ungated:
    # staff can exceed the limit by design. Checked outside the lock; the
    # same-instant race is accepted (see spec, Concurrency).
    if context.enforce_daily_limit &&
       bundle.day_pass_type.daily_limit_reached?(day: date, location: location)
      context.day_pass_type = bundle.day_pass_type
      context.outcome = :sold_out
      return
    end

    # Computed in the lock, announced after it (ADR 0026 — never enqueue a
    # notification inside a transaction).
    office_hold = nil

    bundle.with_lock do
      # C2: re-check inside the lock to prevent concurrent double-schedule of
      # the same date (mirrors ConsumeOnEntry's inner guard).
      if user.day_passes.for_location(location).for_day(date).exists?
        context.outcome = :already_covered
        next
      end

      # `imported: true` skips DayPass member-lifecycle side effects — the burn
      # is the audit record (mirrors ConsumeOnEntry). NOT complimentary: the
      # pass is prepaid and must count toward door-access checks.
      day_pass = DayPass.create!(
        user:          user,
        billable:      user,
        operator:      bundle.operator,
        location:      location,
        day_pass_type: bundle.day_pass_type,
        day:           date,
        imported:      true,
      )

      # T10/ADR 0026: allocate a pool room for a Day Office bundle before
      # burning. Member self-serve (enforce_daily_limit) is strict: the
      # pre-gate above normally catches a sold-out pool, but a concurrent
      # schedule can still win the race between that snapshot and this
      # in-lock attempt — when it does, destroy the just-minted pass and
      # report :sold_out rather than burn for an office that doesn't exist
      # (mirrors AllocateDayOffice's organizer-level backstop). Staff
      # scheduling (no enforce flag) is lenient: it proceeds office-less on a
      # lost race or a sold-out pool — staff judgment, and staff are the ones
      # who then tell the member, so that path stays silent (see below).
      if bundle.day_pass_type.day_office?
        hold = office_hold = DayOffices::Allocator.allocate!(day_pass: day_pass)
        if hold.nil? && context.enforce_daily_limit
          day_pass.destroy!
          context.day_pass_type = bundle.day_pass_type
          context.outcome = :sold_out
          next
        end
      end

      # C1: defer the "how was your visit?" follow_up email for future dates —
      # the member hasn't visited yet. Same-day scheduling (date == today) still
      # fires it immediately, matching the existing ConsumeOnEntry behaviour.
      bundle.burn_locked!(kind: :entry, performed_by: performed_by, day_pass: day_pass,
                          defer_review_email: date > today)
      context.bundle      = bundle
      context.day_pass    = day_pass
      context.office_hold = office_hold
      context.outcome     = :scheduled
    end

    # Member self-serve only. `notify_member` names the semantics
    # `enforce_daily_limit` happens to carry — this schedule was initiated by
    # the MEMBER (mobile redeem_today / pick-a-day), not by staff burning on
    # their behalf — and defaults to it so no caller has to change. Staff
    # scheduling stays deliberately quiet: the admin is standing there telling
    # them, and the lenient branch above may have produced no office at all.
    notify_member = context.notify_member.nil? ? context.enforce_daily_limit : context.notify_member

    if context.outcome == :scheduled && notify_member && office_hold
      # Always publish WHAT would be announced; `defer_notifications` decides
      # WHO announces it. Billing::DayPassBundles::ScheduleDays wraps a whole
      # batch in one transaction and rolls the batch back when any date fails,
      # so enqueuing from in here would hand Sidekiq a job naming a row that
      # may never commit — the worker can pick it up before COMMIT (job
      # discarded on DeserializationError, mailer nil-bails) or after a
      # ROLLBACK. When the batch owns the transaction it also owns the
      # notification, and fires it once the transaction has closed.
      context.notify_day_pass = context.day_pass
      DayOffices::Notify.assigned(day_pass: context.day_pass) unless context.defer_notifications
    end
  rescue DayPassBundle::NoPassesRemaining
    context.outcome = :no_bundle
  end

  private

  # Mirrors ConsumeOnEntry's guards, scoped to the target date instead of
  # today. For a day-office bundle the office is the point, not the access —
  # subscription/lease/reservation coverage must not suppress the mint; only
  # an existing same-date pass does (ADR 0026).
  def already_covered?(date, tz, office: false)
    unless office
      return true if user.has_active_subscription?
      return true if user.has_active_lease?(location)

      day_start = date.in_time_zone(tz).beginning_of_day
      day_end   = date.in_time_zone(tz).end_of_day
      return true if user.reservations.where(cancelled: false)
                         .where(datetime_in: day_start..day_end).exists?
    end

    user.day_passes.for_location(location).for_day(date).exists?
  end

  # usable_on carries the date rule (ADR 0018: the bundle must survive a FUTURE
  # target date; expiring-later-today still covers a same-day schedule — Task 10
  # fix), draw_order the canonical pick. Memoized: this is looked up twice per
  # #call (the already_covered? office check, then the real assignment) and must
  # return the identical row both times — safe because a ScheduleDay instance is
  # one-shot (a fresh instance per .call).
  def eligible_bundle(date, tz)
    return @eligible_bundle if defined?(@eligible_bundle)
    @eligible_bundle = user.day_pass_bundles.usable_on(date, tz).where(location: location).draw_order.first
  end
end

class Api::V1::RoomsController < Api::V1::BaseController
  def index
    location = current_location
    return render json: [] unless location

    rooms = location.rooms.visible.order(:name)

    render json: rooms.map { |r| room_json(r) }
  end

  def availability
    room = current_tenant.rooms.find_by(id: params[:id])
    return render_error("Room not found", status: :not_found) unless room
    date = Date.parse(params[:date]) rescue Date.current

    # Get all reservations for this room on this date
    reservations = room.reservations.where(cancelled: false)
      .where("datetime_in::date = ?", date)
      .order(:datetime_in)

    org_mate_ids = current_api_user&.organization ? current_api_user.organization.users.pluck(:id) : []

    render json: {
      room: room_json(room),
      date: date.to_s,
      reservations: reservations.map { |r| {
        start: r.datetime_in.strftime("%H:%M"),
        end: r.datetime_out.strftime("%H:%M"),
        start_label: r.datetime_in.strftime("%l:%M %p").strip,
        end_label: r.datetime_out.strftime("%l:%M %p").strip,
        user: r.user.name,
        # Flag bookings by the viewer or their org-mates so the picker can show
        # "your team already has this" instead of an unexplained gap.
        mine: r.user_id == current_api_user&.id,
        is_teammate: r.user_id != current_api_user&.id && org_mate_ids.include?(r.user_id),
      }},
    }
  end

  def time_slots
    room = current_tenant.rooms.find_by(id: params[:id])
    return render_error("Room not found", status: :not_found) unless room
    date = Date.parse(params[:date]) rescue Date.current
    location = current_location

    # Generate 15-min slots from open to close. The role-gated hour bounds
    # (members get the full 24h window, non-members are bounded by posted
    # working hours) are computed by start_hour_bounds — shared with
    # booking_times. See the Drew Bray 30-min booking incident, 2026-06.
    start_hour, end_hour = start_hour_bounds(location)

    zone = location&.time_zone || 'UTC'
    slots = []
    # Use addition rather than `change(hour: x)` so end_hour == 24
    # (superadmin all-day window) doesn't raise ArgumentError.
    day_start = date.in_time_zone(zone).beginning_of_day
    current_time = day_start + start_hour.hours
    end_time = day_start + end_hour.hours

    # If this is today, skip past slots. Round up to the next 15-min mark
    # so the user can't pick a start time that's already gone by.
    now_in_zone = Time.current.in_time_zone(zone)
    if date == now_in_zone.to_date
      floor = now_in_zone.change(min: (now_in_zone.min / 15).floor * 15, sec: 0)
      min_start = floor + 15.minutes
      current_time = min_start if current_time < min_start
    end

    # When editing a reservation, exclude it from the overlap check so its
    # own slot shows as available (the backend overlap check excludes self too).
    except_id = params[:exclude_reservation_id].presence

    while current_time < end_time
      available = room.available?(start_time: current_time, duration: 15, except: except_id)
      slots << {
        time: current_time.strftime("%H:%M"),
        hour: current_time.hour,
        label: current_time.strftime("%l:%M %p").strip,
        available: available,
      }
      current_time += 15.minutes
    end

    render json: { room: room_json(room), date: date.to_s, slots: slots }
  end

  def pricing
    room = current_tenant.rooms.find_by(id: params[:id])
    return render_error("Room not found", status: :not_found) unless room
    date = params[:date].present? ? Date.parse(params[:date]) : Date.current
    minutes = (params[:minutes] || 60).to_i

    user = current_api_user
    location = current_location

    # Credit info (if credits enabled)
    credit_info = nil
    if location.try(:credits_enabled?)
      credit_cost = room.try(:credit_cost) || 0
      credit_charge = credit_cost > 0 ? ((credit_cost / 60.0) * minutes).ceil : 0
      credit_info = {
        credits_enabled: true,
        credit_cost_per_hour: credit_cost,
        credit_charge: credit_charge,
        credit_balance: user.credit_balance,
        sufficient_credits: user.credit_balance >= credit_charge,
        credit_price_cents: location.try(:credit_cost_in_cents) || 0,
      }
    end

    sub_info = user.subscription_reservation_charge_info(location, minutes, room: room, at: date.in_time_zone)
    dp_info = user.day_pass_reservation_charge_info(location, date, minutes, room: room)

    # Active subscriber on a plan with no meeting-room limit → rooms are
    # free (unlimited). subscription_reservation_charge_info returns nil
    # in that case, so we'd otherwise fall through to full hourly rate.
    subscriber_unlimited = sub_info.nil? &&
                           user.has_active_subscription? &&
                           user.has_active_subscription_at_location?(location)

    # Members, leaseholders, and staff/owners are never charged the hourly rate
    # for a priced (premium) room — should_charge_for_room? is the SAME gate
    # SaveRoomReservation uses to set `paid`, so the quote always matches what's
    # actually charged. NOTE: day-pass holders are NOT exempt for premium rooms
    # (a day pass doesn't cover them) — they must see + pay the hourly rate.
    exempt_from_room_charge = if room.hourly_rate_in_cents.to_i > 0
      !user.should_charge_for_room?(room, date)            # premium room: day-passers pay
    else
      !user.should_charge_for_reservation?(location, date) # free room: unchanged
    end

    base = if subscriber_unlimited
      {
        included_in_plan: true,
        charge_type: 'free',
        estimated_cost: 0,
        plan_minutes_remaining: nil,
        plan_minutes_total: nil,
        overage_rate: nil,
        source: 'subscription_unlimited',
      }
    elsif sub_info
      {
        included_in_plan: sub_info[:charge_type] == :free,
        charge_type: sub_info[:charge_type].to_s,
        estimated_cost: sub_info[:overage_amount_in_cents] || 0,
        plan_minutes_remaining: sub_info[:remaining_free],
        plan_minutes_total: sub_info[:included_minutes],
        used_minutes: sub_info[:used_minutes],
        overage_rate: sub_info[:overage_rate_in_cents],
        source: 'subscription',
      }
    elsif dp_info
      {
        included_in_plan: dp_info[:charge_type] == :free,
        charge_type: dp_info[:charge_type].to_s,
        estimated_cost: dp_info[:overage_amount_in_cents] || 0,
        plan_minutes_remaining: dp_info[:remaining_free],
        plan_minutes_total: nil,
        overage_rate: dp_info[:overage_rate_in_cents],
        source: 'day_pass',
      }
    elsif exempt_from_room_charge
      {
        included_in_plan: true,
        charge_type: 'free',
        estimated_cost: 0,
        plan_minutes_remaining: nil,
        plan_minutes_total: nil,
        overage_rate: nil,
        source: 'exempt',
      }
    else
      hourly_rate = room.hourly_rate_in_cents || 0
      estimated = (hourly_rate * minutes / 60.0).round
      {
        included_in_plan: false,
        charge_type: hourly_rate > 0 ? 'full' : 'free',
        estimated_cost: estimated,
        plan_minutes_remaining: nil,
        plan_minutes_total: nil,
        overage_rate: nil,
        source: 'hourly',
      }
    end

    base[:credits] = credit_info if credit_info

    # Coverage check: if the user has no active subscription, no day pass
    # for this date, and no active lease, they need a day pass to book.
    # Exception: priced rooms — the hourly rate covers access.
    is_priced_room = room.hourly_rate_in_cents.to_i > 0
    needs_cov = !is_priced_room &&
                !user.has_active_subscription? &&
                !user.has_active_day_pass?(date) &&
                !user.has_active_lease?(location) &&
                !user.admin_or_manager?(location) &&
                !user.superadmin?

    if needs_cov
      suggested = pick_default_room_booking_day_pass_type(location)
      if suggested
        base[:needs_day_pass] = true
        base[:day_pass] = {
          type_id: suggested.id,
          name: suggested.name,
          amount_in_cents: suggested.amount_in_cents,
          included_meeting_room_minutes: suggested.included_meeting_room_minutes,
          overage_rate_in_cents: suggested.overage_rate_in_cents,
          date: date.to_s,
        }

        # Project the same overage logic as if this day pass were already
        # purchased, so the summary can warn about overages up front.
        # Priced rooms never count against day pass allowance.
        if room.hourly_rate_in_cents.to_i == 0
          included = suggested.included_meeting_room_minutes
          if included.present? && minutes > included
            over_min = minutes - included
            over_min_rounded = (over_min / 15.0).ceil * 15
            over_rate_per_min = (suggested.overage_rate_in_cents || 0) / 60.0
            over_cents = (over_rate_per_min * over_min_rounded).to_i
            base[:charge_type] = 'partial_overage'
            base[:estimated_cost] = over_cents
            base[:plan_minutes_remaining] = included
            base[:plan_minutes_total] = included
            base[:overage_rate] = suggested.overage_rate_in_cents
            base[:source] = 'projected_day_pass'
            base[:included_in_plan] = false
          elsif included.present?
            base[:charge_type] = 'free'
            base[:estimated_cost] = 0
            base[:plan_minutes_remaining] = included - minutes
            base[:plan_minutes_total] = included
            base[:source] = 'projected_day_pass'
            base[:included_in_plan] = true
          end
        end
      else
        base[:needs_day_pass] = true
        base[:day_pass] = nil
      end
    else
      base[:needs_day_pass] = false
    end

    # Reserve-time bundle redemption (Phase 5 / ADR 0015): offer "use 1 pass for
    # today" when the booking would otherwise auto-add a day pass (needs_cov ⇒ $0
    # room + uncovered + not subscribed/leased/admin — the same coarse guards as
    # RedeemBundlePass) and the booker holds prepaid bundle passes usable for the
    # requested date (usable_on — a pack expiring before the booked day must not
    # be offered, ADR 0018). The finer once-per-business-day-window burn check
    # stays in the interactor (idempotent), so an optimistic flag here can never
    # double-spend a pass.
    bundle_tz = ActiveSupport::TimeZone[location&.time_zone.presence || "UTC"]
    bundle_passes_remaining = user.day_pass_bundles.usable_on(date, bundle_tz).where(location: location)
                                  .map { |b| b.passes_remaining.to_i }.sum
    base[:bundle_passes_remaining] = bundle_passes_remaining
    base[:bundle_pass_redeemable] = needs_cov && bundle_passes_remaining > 0

    # ADR 0019 — included-room coverage state + prospective overage for the
    # pre-booking confirm. `:not_applicable` for paid rooms / non-included rooms.
    coverage = Billing::Reservations::CoverageState.for(user: user, room: room, date: date, location: location)
    covering_type = case coverage.outcome
                    when :bundle_available then coverage.bundle&.day_pass_type
                    when :reusable_pass    then coverage.reusable_pass&.day_pass_type
                    when :needs_purchase   then coverage.day_pass_type
                    else user.day_passes.for_location(location).for_day(date).first&.day_pass_type
                    end
    base[:coverage] = {
      state: coverage.outcome,
      bundle_passes_remaining: coverage.passes_remaining,
      day_pass_amount_in_cents: coverage.amount_cents,
      reusable_from_date: coverage.reusable_pass&.day&.iso8601,
      overage_in_cents: Billing::Reservations::OveragePreview.cents(
        user: user, location: location, date: date, minutes: minutes, day_pass_type: covering_type),
    }

    render json: base
  end

  def reserve_now
    location = current_location
    return render json: { rooms: [] } unless location

    user = current_api_user
    zone = ActiveSupport::TimeZone[location.time_zone] || Time.zone
    now = Time.current.in_time_zone(zone).change(sec: 0)

    # Posted-hours bound: Reserve Now starts a booking RIGHT NOW, so when the
    # location is closed there is nothing an hour-bounded user can book —
    # return every room as unavailable with the next opening time, so the
    # app's existing "free at…" list renders a truthful closed state. (Nash,
    # 2026-08-07: an after-hours Reserve Now would re-open the door through
    # the reservation ±window even with day-pass door access hours-bounded.)
    unless user.books_outside_posted_hours?(location) || user.admin_or_manager?(location) || location.within_posted_hours?(now)
      reopen_label = next_open_label(location, now, zone)
      closed_rooms = location.rooms.visible.map do |room|
        {
          id: room.id, name: room.name, capacity: room.capacity,
          hourly_rate: room.hourly_rate_in_cents,
          amenities: room.amenities.pluck(:name),
          add_ons: room.amenity_add_ons,
          amenity_features: room.amenity_feature_names,
          features: room.features || [],
          available: false,
          available_at: reopen_label,
        }
      end
      preferred = user.preferred_meeting_duration.to_i
      return render json: {
        rooms: closed_rooms,
        no_rooms_available: true,
        closed: true,
        message: "#{location.name} is closed right now — open #{location.posted_hours_label}.",
        start_time: now.iso8601,
        preferred_duration: preferred > 0 ? preferred : 60,
      }
    end

    # Reserve Now starts the booking RIGHT NOW. End-times still align
    # to 15-minute marks (so the slider's 15/30/45/60 picks land on
    # familiar times), and the lead-in minutes between now and the
    # next 15-min mark roll into the booked total. Example: at 3:39
    # PM with a 30-min slider pick, the booking is 3:39 → 4:15 PM
    # (36 effective minutes billed).
    start_time = now
    remainder = now.min % 15
    next_quarter = remainder == 0 ? now : now + (15 - remainder).minutes
    next_quarter = next_quarter.change(sec: 0)
    lead_in_minutes = ((next_quarter - now) / 60).to_i

    duration = user.preferred_meeting_duration.to_i
    duration = 60 if duration <= 0
    effective_minutes = duration + lead_in_minutes

    # Find available rooms — overlap is checked against the full
    # effective window (now through end-of-slider-pick).
    end_time = start_time + effective_minutes.minutes
    booked_room_ids = Reservation.where(room: location.rooms.visible)
      .where("datetime_in < ? AND (datetime_in + minutes * interval '1 minute') > ?", end_time, start_time)
      .where(cancelled: false)
      .pluck(:room_id).uniq

    available_rooms = location.rooms.visible.where.not(id: booked_room_ids)
    # ADR 0019: show a not-yet-covered user the included rooms too (not just
    # cash-rentable ones) so tapping one surfaces the buy-a-day-pass confirm.
    available_rooms = available_rooms.rentable_or_day_pass_included unless user.can_see_all_rooms?(location, start_time.to_date) rescue available_rooms

    available_list = available_rooms.to_a

    if available_list.empty?
      # No rooms — return unavailable list with free times
      all_rooms = location.rooms.visible.map do |room|
        current_booking = room.reservations.where(cancelled: false)
          .where("datetime_in <= ? AND (datetime_in + minutes * interval '1 minute') > ?", Time.current, Time.current)
          .first
        overlap = room.reservations.where(cancelled: false)
          .where("datetime_in < ? AND (datetime_in + minutes * interval '1 minute') > ?", end_time, start_time)
          .order(:datetime_in).first unless current_booking
        free_at = current_booking&.datetime_out || overlap&.datetime_out
        {
          id: room.id, name: room.name, capacity: room.capacity,
          hourly_rate: room.hourly_rate_in_cents,
          amenities: room.amenities.pluck(:name),
          add_ons: room.amenity_add_ons,
          amenity_features: room.amenity_feature_names,
          features: room.features || [],
          available: false,
          available_at: free_at&.in_time_zone(zone)&.strftime("%l:%M %p")&.strip,
        }
      end.sort_by { |r| r[:available_at] || '' }

      return render json: {
        rooms: all_rooms,
        no_rooms_available: true,
        start_time: start_time.iso8601,
        preferred_duration: duration,
      }
    end

    # Pick the hero room — preferred, then cheapest, then first
    preferred = available_list.find { |r| r.id == user.preferred_room_id }
    hero = preferred || available_list.min_by { |r| r.hourly_rate_in_cents.to_i } || available_list.first

    hero_cap = hero.max_bookable_minutes(admin: false)
    max_duration = [(hero.calculate_max_continuous_duration(start_time: start_time, max_minutes: hero_cap) rescue 240), hero_cap].min

    # Pricing for hero room — uses the effective booked minutes
    # (slider pick + lead-in) so the displayed cost matches what the
    # member is actually billed at confirm.
    sub_info = user.subscription_reservation_charge_info(location, effective_minutes) rescue nil
    dp_info = user.day_pass_reservation_charge_info(location, start_time.to_date, effective_minutes) rescue nil

    should_charge = user.should_charge_for_reservation?(location, start_time.to_date) rescue true
    hourly = hero.hourly_rate_in_cents / 100.0
    total_price = hourly * (effective_minutes / 60.0)
    included = !should_charge && hero.hourly_rate_in_cents > 0

    if sub_info && sub_info[:charge_type] == :partial_overage
      included = false
      total_price = sub_info[:overage_amount_in_cents] / 100.0
    end
    if dp_info && dp_info[:charge_type] == :partial_overage
      included = false
      total_price = dp_info[:overage_amount_in_cents] / 100.0
    end

    included_minutes_remaining = sub_info&.dig(:remaining_free) || dp_info&.dig(:remaining_free)
    overage_rate_per_hour_cents = sub_info&.dig(:overage_rate_in_cents) || dp_info&.dig(:overage_rate_in_cents)
    has_plan = sub_info.present? || dp_info.present?

    room_json = ->(r, is_available, available_at = nil) {
      {
        id: r.id, name: r.name, capacity: r.capacity,
        description: r.description,
        hourly_rate: r.hourly_rate_in_cents,
        amenities: r.amenities.pluck(:name),
        add_ons: r.amenity_add_ons,
        amenity_features: r.amenity_feature_names,
        features: r.features || [],
        available: is_available,
        available_at: available_at,
        preferred: r.id == user.preferred_room_id,
        photo_url: (r.photo.attached? ? url_for(r.photo) : nil rescue nil),
        charge: room_charge(r, user, location, start_time.to_date, effective_minutes, start_time),
      }
    }

    other_available = available_list.reject { |r| r.id == hero.id }.sort_by { |r| r.hourly_rate_in_cents.to_i }
    unavailable_ids = location.rooms.visible.where.not(id: available_list.map(&:id)).pluck(:id)
    unavailable = location.rooms.visible.where(id: unavailable_ids).map do |r|
      current_booking = r.reservations.where(cancelled: false)
        .where("datetime_in <= ? AND (datetime_in + minutes * interval '1 minute') > ?", Time.current, Time.current)
        .first
      overlap = r.reservations.where(cancelled: false)
        .where("datetime_in < ? AND (datetime_in + minutes * interval '1 minute') > ?", end_time, start_time)
        .order(:datetime_in).first unless current_booking
      free_at = current_booking&.datetime_out || overlap&.datetime_out
      room_json.call(r, false, free_at&.in_time_zone(zone)&.strftime("%l:%M %p")&.strip)
    end

    render json: {
      hero_room: room_json.call(hero, true),
      available_rooms: other_available.map { |r| room_json.call(r, true) },
      unavailable_rooms: unavailable,
      start_time: start_time.iso8601,
      start_time_label: start_time.strftime("%-l:%M %p"),
      lead_in_minutes: lead_in_minutes,
      preferred_duration: duration,
      max_duration: max_duration,
      total_price: total_price,
      included_in_plan: included,
      included_minutes_remaining: included_minutes_remaining,
      should_charge: should_charge || (sub_info&.dig(:charge_type) == :partial_overage) || (dp_info&.dig(:charge_type) == :partial_overage),
      # Client uses these to compute effective price per room × current slider duration:
      pricing_context: {
        has_plan: has_plan,
        minutes_remaining: included_minutes_remaining.to_i,
        overage_rate_per_hour_cents: overage_rate_per_hour_cents.to_i,
        subscriber_unlimited: user.has_active_subscription_at_location?(location) && sub_info.nil?,
        plan_label: sub_info ? 'plan' : (dp_info ? 'day pass' : nil),
      },
    }
  end

  # GET /api/v1/rooms/available?date=&time=HH:MM&minutes=&exclude_reservation_id=
  # Rooms free for an explicit future window (when-first booking). `time` is
  # the location-local start (24h "HH:MM"); minutes is the duration.
  def available
    location = current_location
    return render json: { available_rooms: [], unavailable_rooms: [], no_rooms_available: true } unless location

    user = current_api_user
    zone = location.time_zone.presence || 'UTC'
    date = params[:date].present? ? Date.parse(params[:date]) : Date.current
    minutes = (params[:minutes] || 60).to_i
    return render_error('Invalid duration') if minutes <= 0

    raw_time = params[:time].to_s
    unless raw_time.match?(/\A\d{1,2}:\d{2}\z/)
      return render_error('Invalid time')
    end
    start_time = (ActiveSupport::TimeZone[zone].parse("#{date} #{raw_time}") rescue nil)
    return render_error('Invalid time') if start_time.nil?
    except_id = params[:exclude_reservation_id].presence

    # `include_hidden` is an admin-only carveout (e.g. Choose Folsom's
    # auditorium is an intentionally-hidden room only admins may book). Gated
    # on admin_of_location? so members can never surface hidden rooms by
    # passing the flag.
    include_hidden = user.admin_of_location?(location) &&
                     ActiveModel::Type::Boolean.new.cast(params[:include_hidden])
    rooms = include_hidden ? location.rooms.active : location.rooms.visible
    # Beyond the free-room cap only priced (conference) rooms are bookable
    # for non-staff — drop free rooms from the list here so the member sees
    # only real options instead of failing at confirm. Staff keep all rooms
    # (their cap is 12h across the board).
    if minutes > Room::FREE_ROOM_MAX_BOOKING_MINUTES && !user.admin_of_location?(location)
      rooms = rooms.where("hourly_rate_in_cents > 0")
    end
    # ADR 0019: include day-pass-unlockable rooms for not-yet-covered users so
    # the buy-a-day-pass confirm surfaces instead of hiding included rooms.
    rooms = (rooms.rentable_or_day_pass_included rescue rooms) unless user.can_see_all_rooms?(location, date)

    avail, unavail = rooms.to_a.partition do |r|
      r.available?(start_time: start_time, duration: minutes, except: except_id)
    end

    # Client computes per-room price = hourly_rate × duration, or uses the
    # plan/day-pass context — identical to the reserve_now contract.
    sub_info = (user.subscription_reservation_charge_info(location, minutes, at: start_time) rescue nil)
    dp_info  = (user.day_pass_reservation_charge_info(location, date, minutes) rescue nil)
    included_minutes_remaining = sub_info&.dig(:remaining_free) || dp_info&.dig(:remaining_free)
    overage_rate = sub_info&.dig(:overage_rate_in_cents) || dp_info&.dig(:overage_rate_in_cents)
    # Exempt members/admins/leaseholders are never charged the hourly rate,
    # even for a priced room. Surface it (as #reserve_now does) so the room
    # list reads Free instead of quoting hourly_rate × duration.
    should_charge = (user.should_charge_for_reservation?(location, start_time.to_date) rescue true)
    should_charge ||= sub_info&.dig(:charge_type) == :partial_overage
    should_charge ||= dp_info&.dig(:charge_type) == :partial_overage

    end_time = start_time + minutes.minutes
    render json: {
      start_time: start_time.iso8601,
      start_time_label: start_time.strftime("%-l:%M %p").strip,
      minutes: minutes,
      no_rooms_available: avail.empty?,
      available_rooms: avail.sort_by { |r| r.hourly_rate_in_cents.to_i }.map { |r| room_card(r, true).merge(charge: room_charge(r, user, location, date, minutes, start_time)) },
      unavailable_rooms: unavail.map { |r| room_card(r, false, next_free_at(r, start_time, end_time, zone)) },
      pricing_context: {
        should_charge: should_charge,
        has_plan: sub_info.present? || dp_info.present?,
        minutes_remaining: included_minutes_remaining.to_i,
        overage_rate_per_hour_cents: overage_rate.to_i,
        subscriber_unlimited: user.has_active_subscription_at_location?(location) && sub_info.nil?,
        plan_label: sub_info ? 'plan' : (dp_info ? 'day pass' : nil),
      },
    }
  end

  # GET /api/v1/rooms/booking_times?date=  → role-gated 15-min start times.
  def booking_times
    location = current_location
    return render json: { times: [] } unless location
    date = Date.parse(params[:date]) rescue Date.current
    zone = location&.time_zone || 'UTC'
    start_hour, end_hour = start_hour_bounds(location)

    day_start = date.in_time_zone(zone).beginning_of_day
    current_time = day_start + start_hour.hours
    end_time = day_start + end_hour.hours

    now_in_zone = Time.current.in_time_zone(zone)
    if date == now_in_zone.to_date
      floor = now_in_zone.change(min: (now_in_zone.min / 15).floor * 15, sec: 0)
      min_start = floor + 15.minutes
      current_time = min_start if current_time < min_start
    end

    times = []
    while current_time < end_time
      times << { time: current_time.strftime("%H:%M"), hour: current_time.hour,
                 label: current_time.strftime("%l:%M %p").strip }
      current_time += 15.minutes
    end
    render json: { date: date.to_s, times: times }
  end

  private

  # Role-gated bookable hour bounds for a location. Members with 24/7 access
  # (active subscription/lease) and superadmins get the full 0..24 window;
  # everyone else is bounded by posted working hours. Mirrors time_slots.
  # "5:00 AM" for later today, or "Sat 5:00 AM" when the next opening is
  # tomorrow — the next instant the posted-hours window begins (time-of-day
  # rule; the open_<day> staffed-days flags don't bound day-pass access).
  def next_open_label(location, from, zone)
    m = location.working_day_start.to_s.match(/\A(\d{1,2}):(\d{2})\z/)
    return nil unless m

    (0..1).each do |i|
      candidate = (from.to_date + i).in_time_zone(zone).change(hour: m[1].to_i, min: m[2].to_i)
      next unless candidate > from
      label = candidate.strftime("%l:%M %p").strip
      return i.zero? ? label : "#{candidate.strftime('%a')} #{label}"
    end
    nil
  end

  def start_hour_bounds(location)
    parse_hour = ->(val, default) {
      return default if val.nil?
      val.is_a?(String) ? val.split(':').first.to_i : val.to_i
    }
    start_hour = parse_hour.call(location&.working_day_start, 8)
    end_hour   = parse_hour.call(location&.working_day_end, 18)
    if current_api_user&.books_outside_posted_hours?(location)
      [0, 24]
    else
      [start_hour, end_hour]
    end
  end

  # Per-room charge + coverage label for the room LIST, computed with the SAME
  # rules as the /rooms/:id/pricing summary so the list can never disagree with
  # it. Priced rooms use should_charge_for_room? (day-passers DO pay premium
  # rooms — a day pass covers free rooms + included minutes, not hourly rooms);
  # $0 rooms use should_charge_for_reservation? plus any plan/day-pass overage.
  # Returns { cents:, label: } — when label is present the client shows it
  # ("Included with …"); otherwise it shows the dollar amount.
  def room_charge(room, user, location, day, minutes, at = nil)
    if room.hourly_rate_in_cents.to_i > 0
      if user.should_charge_for_room?(room, day)
        { cents: (room.hourly_rate_in_cents.to_i * minutes / 60.0).round, label: nil }
      else
        { cents: 0, label: included_with_label(user, location, day) }
      end
    else
      # $0 room. Compute coverage the SAME way the /pricing summary does — per
      # room, with the booking's minutes — so a plan/day-pass OVERAGE (included
      # meeting-room minutes exceeded) surfaces as a real charge FIRST, instead of
      # wrongly reading "Included" while the booker is actually billed the overage.
      sub_info = (user.subscription_reservation_charge_info(location, minutes, room: room, at: at) rescue nil)
      dp_info  = (user.day_pass_reservation_charge_info(location, day, minutes, room: room) rescue nil)
      info = sub_info || dp_info
      over = info&.dig(:overage_amount_in_cents).to_i
      if over > 0
        { cents: over, label: nil }
      elsif !user.should_charge_for_reservation?(location, day) || info
        { cents: 0, label: included_with_label(user, location, day) }
      else
        { cents: 0, label: "Day pass required" }
      end
    end
  end

  # Why a room reads as covered, for the list label.
  def included_with_label(user, location, day)
    return "Included with membership" if user.member?(location)
    return "Included with office" if user.has_active_lease?
    return "Included with day pass" if user.has_active_day_pass?(day)
    "Free"
  end

  def room_card(room, is_available, available_at = nil)
    room_json(room).merge(available: is_available, available_at: available_at,
                          preferred: room.id == current_api_user.preferred_room_id)
  end

  def next_free_at(room, start_time, end_time, zone)
    overlap = room.reservations.where(cancelled: false)
                  .where("datetime_in < ? AND (datetime_in + minutes * interval '1 minute') > ?", end_time, start_time)
                  .order(:datetime_in).first
    overlap&.datetime_out&.in_time_zone(zone)&.strftime("%-l:%M %p")&.strip
  end

  # Prefer the day pass type explicitly marked as the default for room
  # bookings. Fall back to cheapest non-free, non-Day-Office type — excluded
  # by KIND (was a %office% name-match), same preference order CoverageState
  # uses for its suggestion (ADR 0026).
  def pick_default_room_booking_day_pass_type(location)
    DayPassType.suggested_standard_for(location)
  end

  def room_json(room)
    {
      id: room.id,
      name: room.name,
      capacity: room.capacity,
      description: room.description,
      hourly_rate: room.hourly_rate_in_cents,
      amenities: room.amenities.pluck(:name),
      add_ons: room.amenity_add_ons,
      amenity_features: room.amenity_feature_names,
      features: room.features || [],
      rentable: room.rentable?,
      available: (room.available_now? rescue false),
      photo_url: (room.photo.attached? ? url_for(room.photo) : nil rescue nil),
    }
  end
end

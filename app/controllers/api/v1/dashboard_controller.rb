class Api::V1::DashboardController < Api::V1::BaseController
  include LandingHelper
  include Api::V1::DoorUnlocking

  def show
    location = current_location
    user = current_api_user

    # The host greeting is NOT auto-created here anymore. The WelcomeScreen
    # chat card renders the greeting client-side; a MemberFeedback thread is
    # only opened when the member actually replies (member_feedbacks#create
    # seeds the greeting into the new thread then). Page-load auto-creation
    # filled the admin inbox with one-sided "Welcome!" threads for every
    # visitor — impossible to keep track of real conversations.

    today_reservations = user.reservations.where(cancelled: false).where("datetime_in::date = ?", Date.current)
    next_reservation = user.reservations.where(cancelled: false).where("datetime_in > ?", Time.current).order(:datetime_in).first

    announcements = Announcement.where(operator: current_tenant)
      .where("created_at > ?", 7.days.ago)
      .order(created_at: :desc)
      .limit(3)

    events = Event.where(location: location).approved.future.order(:starts_at).limit(5)
    user_rsvp_ids = user.rsvps.pluck(:event_id)

    # Doors for unlock buttons — sorted by user's most-used first. Gated on
    # the SAME predicate the unlock endpoint uses (user_can_access_building?),
    # so buttons show if and only if a tap would succeed. The previous gate
    # (Permissions#has_building_access?) had no reservation clause, so a
    # reservation-only visitor inside their ±window (ADR 0013) — whom unlock
    # would happily admit — saw no keys at all and was stranded at the door.
    doors =
      if location && user_can_access_building?(user, location)
        scope = location.doors.where(available: true)
        # Treat unset/NULL private as public (see Api::V1::DoorsController#index).
        scope = scope.where(private: [false, nil]) unless user.admin?
        door_usage = DoorPunch.where(user: user, door: scope).group(:door_id).count
        scope.sort_by { |d| -(door_usage[d.id] || 0) }
      else
        []
      end

    # Unread admin replies waiting for the member. Uses MemberFeedback#last_read_at
    # vs feedback_replies.created_at — set in MemberFeedback#has_unread_replies?.
    # (The previous query referenced a `status` column that doesn't exist and was
    # silently rescuing to 0, so the RN badge never lit up.)
    open_tickets = user.member_feedbacks.includes(:feedback_replies).count(&:has_unread_replies?)

    render json: {
      reservations_today: today_reservations.count,
      open_ticket_count: open_tickets,
      doors: doors.map { |d| { id: d.id, name: d.name } },
      visitors_today: location ? DoorPunch.where(door: location.doors).where("created_at::date = ?", Date.current).distinct.count(:user_id) : 0,
      day_passes_today: location ? location.day_passes.where(day: Date.current).count : 0,
      next_reservation: next_reservation ? {
        id: next_reservation.id,
        room_name: next_reservation.room.name,
        date: next_reservation.datetime_in.strftime("%B %e, %Y"),
        time: next_reservation.datetime_in.strftime("%l:%M %p").strip,
        access_opens_label: next_reservation.access_opens_at.strftime("%l:%M %p").strip,
        access_window_minutes: next_reservation.building_access_window_minutes,
        duration: "#{next_reservation.minutes} min",
      } : nil,
      announcements: announcements.map { |a| { body: a.body.to_s.truncate(200), date: a.created_at.strftime("%b %e") } },
      events: events.map { |e| {
        id: e.id,
        title: e.title,
        date: e.starts_at.strftime("%b %e at %l:%M %p").strip,
        rsvped: user_rsvp_ids.include?(e.id),
      } },
      has_active_subscription: user.has_active_subscription?,
      active_day_pass: begin
        zone = location&.time_zone.presence || 'UTC'
        local_today = Time.current.in_time_zone(zone).to_date
        # A day-passer "today" = any pass for local today OR upcoming in the next week.
        pass = user.day_passes.where(day: local_today..(local_today + 7)).order(:day).first
        pass ? {
          id: pass.id,
          day: pass.day,
          type_name: pass.day_pass_type&.name,
          is_today: pass.day == local_today,
        } : nil
      end,
      location_info: location ? {
        name: location.name,
        address: [location.building_address, location.city, location.state, location.zip].compact.reject(&:blank?).join(', '),
        wifi_name: location.wifi_name,
        wifi_password: location.wifi_password,
        building_access_instructions: location.building_access_instructions,
        contact_name: location.contact_name,
        contact_phone: location.contact_phone,
        contact_email: location.contact_email,
        hours: begin
          fmt = ->(v) {
            return nil if v.nil?
            h = v.is_a?(String) ? v.split(':').first.to_i : v.to_i
            suffix = h >= 12 ? 'PM' : 'AM'
            h12 = h % 12
            h12 = 12 if h12 == 0
            "#{h12} #{suffix}"
          }
          s = fmt.call(location.working_day_start)
          e = fmt.call(location.working_day_end)
          (s && e) ? "#{s} – #{e}" : nil
        end,
      } : nil,
    }
  end

  def onboarding_status
    user = current_api_user
    location = current_location
    pending_sub = user.subscriptions.pending.first

    plan_step = if pending_sub
      "Plan selected: #{pending_sub.plan.name}"
    elsif user.day_passes.any?
      "Day pass purchased"
    elsif user.reservations.any?
      "Room reserved"
    else
      "No plan selected yet"
    end

    # Resolve a host the same way the web chat card does (space_host_for:
    # location.space_host → first GM at the location → first operator admin,
    # phone/email preferring the location's contact columns) so operators
    # that never filled in the operator-level contact_* columns still get a
    # chat card on the mobile Welcome/checkout flow.
    host = space_host_for(location)

    render json: {
      has_plan: pending_sub.present?,
      has_day_pass: user.day_passes.any?,
      has_reservation: user.reservations.any?,
      has_billing: user.has_billing_for_location?(location),
      plan_step: plan_step,
      approved: user.approved?,
      contact_name: current_tenant.contact_name.presence || host&.name,
      contact_phone: current_tenant.contact_phone.presence || location&.contact_phone.presence || host&.phone,
      contact_email: current_tenant.contact_email.presence || location&.contact_email.presence || host&.email,
    }
  end
end

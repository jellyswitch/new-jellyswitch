class Api::V1::DashboardController < Api::V1::BaseController
  def show
    location = current_location
    user = current_api_user

    today_reservations = user.reservations.where(cancelled: false).where("datetime_in::date = ?", Date.current)
    next_reservation = user.reservations.where(cancelled: false).where("datetime_in > ?", Time.current).order(:datetime_in).first

    announcements = Announcement.where(operator: current_tenant)
      .where("created_at > ?", 7.days.ago)
      .order(created_at: :desc)
      .limit(3)

    events = Event.where(location: location).approved.future.order(:starts_at).limit(5)
    user_rsvp_ids = user.rsvps.pluck(:event_id)

    # Doors for unlock buttons — sorted by user's most-used first
    doors = location ? location.doors.where(available: true) : []
    doors = doors.where(private: false) unless user.admin?
    door_usage = DoorPunch.where(user: user, door: doors).group(:door_id).count
    doors = doors.sort_by { |d| -(door_usage[d.id] || 0) }

    # Open feedback tickets
    open_tickets = user.member_feedbacks.where(status: ['open', nil]).count rescue 0

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

    render json: {
      has_plan: pending_sub.present?,
      has_day_pass: user.day_passes.any?,
      has_reservation: user.reservations.any?,
      has_billing: user.has_billing_for_location?(location),
      plan_step: plan_step,
      approved: user.approved?,
      contact_name: current_tenant.contact_name,
      contact_phone: current_tenant.contact_phone,
      contact_email: current_tenant.contact_email,
    }
  end
end

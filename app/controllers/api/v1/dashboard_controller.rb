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

    events = Event.where(location: location).future.order(:starts_at).limit(5)
    user_rsvp_ids = user.rsvps.pluck(:event_id)

    render json: {
      reservations_today: today_reservations.count,
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

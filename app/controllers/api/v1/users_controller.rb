class Api::V1::UsersController < Api::V1::BaseController
  def me
    user = current_api_user
    render json: {
      id: user.id,
      name: user.name,
      email: user.email,
      phone: user.phone,
      bio: user.bio,
      linkedin: user.linkedin,
      twitter: user.twitter,
      website: user.website,
      approved: user.approved?,
      role: user.role,
      admin: user.admin?,
      superadmin: user.superadmin?,
      location: user.original_location&.name,
      operator: user.operator.name,
      has_profile_photo: user.has_profile_photo?,
      profile_photo_url: (user.profile_photo.attached? ? url_for(user.profile_photo) : nil rescue nil),
      credit_balance: user.credit_balance,
      location_id: user.current_location_id || user.original_location_id,
      operator_subdomain: user.operator.subdomain,
      features: location_features(user),
      # Scope to .visible so hidden locations (test scratchpads, archived
      # spaces) don't surface in the React Native LocationSwitchScreen — that
      # screen renders `response.data.locations` directly.
      locations: user.operator.locations.visible.map { |l| { id: l.id, name: l.name } },
      # iBeacons the device should start monitoring for auto-unlock-on-approach.
      # Scoped to the operator's visible locations so a member with cross-
      # location access doesn't have to re-fetch when switching spaces. Beacons
      # without an assigned door are skipped — they can't unlock anything yet.
      # Membership and door-permission checks still happen server-side at
      # /api/v1/door/auto_unlock time, so listing a beacon here is safe even
      # for locations the user isn't currently entitled to enter.
      beacons: user.operator.locations.visible.flat_map { |l|
        l.beacons.available.where.not(door_id: nil).map { |b|
          {
            identifier:    "beacon-#{b.id}",
            uuid:          b.uuid,
            major:         b.major,
            minor:         b.minor,
            name:          b.name,
            door_name:     b.door&.name,
            location_id:   l.id,
            location_name: l.name,
          }
        }
      },
      terms_accepted: user.terms_accepted_at.present?,
      has_terms_of_service: user.operator.terms_of_service.attached?,
      terms_of_service_url: user.operator.terms_of_service.attached? ? Rails.application.routes.url_helpers.rails_blob_url(user.operator.terms_of_service, host: request.host_with_port) : nil,
      preferred_room_id: user.preferred_room_id,
      preferred_meeting_duration: user.preferred_meeting_duration,
      marketing_opt_in: user.try(:marketing_consent),
      organization_id: user.try(:organization_id),
      can_submit_events: (
        loc = user.current_location || user.original_location
        user.has_active_subscription? ||
          (loc.present? && user.has_active_lease?(loc)) ||
          user.admin_or_manager?(loc) ||
          user.superadmin?
      ),
      has_active_subscription: user.has_active_subscription?,
      # Operator-set cancellation policy. Mobile uses these to show
      # the right cancel-button copy ("full refund" vs "you'll forfeit
      # the hold") before the member confirms.
      cancellation_window_hours: user.operator&.try(:cancellation_window_hours) || 0,
      refund_fee_percent: user.operator&.try(:refund_fee_percent) || 0,
      # "Has a usable pass" — today or any future date. Past-only passes
      # don't count, otherwise the WelcomeScreen "Plan or Pass" stepper
      # would tick green for a member whose passes are all expired.
      has_day_pass: user.day_passes.where("day >= ?", Date.current).any?,
      location_hours: begin
        loc = user.current_location || user.original_location
        parse = ->(v) { v.is_a?(String) ? v.split(':').first.to_i : v.to_i }
        {
          start_hour: parse.call(loc&.working_day_start),
          end_hour: parse.call(loc&.working_day_end),
          time_zone: loc&.time_zone,
        }
      end,
      # Dates where the user has a day pass — lets mobile filter rooms
      # per-date (premium-only when no coverage on selected date).
      day_pass_days: user.day_passes.where("day >= ?", Date.current - 1).pluck(:day).map(&:to_s),
      has_billing: begin
        loc = user.current_location || user.original_location
        loc.present? && user.card_added_for_location?(loc)
      end,
      has_active_coverage: begin
        loc = user.current_location || user.original_location
        zone = loc&.time_zone.presence || 'UTC'
        today = Time.current.in_time_zone(zone).to_date
        # Coverage = usable today. An upcoming pass doesn't count — user
        # should still see the welcome/onboarding flow (with an
        # "upcoming pass" shortcut) until their pass day actually hits.
        user.has_active_subscription? ||
          user.day_passes.where(day: today).any? ||
          (loc.present? && user.has_active_lease?(loc)) ||
          user.admin_or_manager?(loc) ||
          user.superadmin?
      end,
    }
  end

  def update
    if current_api_user.update(user_params)
      render json: { success: true }
    else
      render_error(current_api_user.errors.full_messages.first)
    end
  end

  def change_password
    user = current_api_user
    unless user.authenticate(params[:current_password])
      return render_error('Current password is incorrect')
    end

    if params[:new_password].length < 6
      return render_error('New password must be at least 6 characters')
    end

    user.password = params[:new_password]
    if user.save
      render json: { success: true }
    else
      render_error(user.errors.full_messages.first)
    end
  end

  def upload_profile_photo
    if params[:photo].blank?
      return render_error('No photo provided')
    end

    current_api_user.profile_photo.attach(params[:photo])
    render json: { success: true, has_profile_photo: true }
  end

  def switch_location
    location = current_tenant.locations.find(params[:location_id])
    current_api_user.update(current_location: location)
    render json: { success: true, location: location.name }
  rescue ActiveRecord::RecordNotFound
    render_error('Location not found', status: :not_found)
  end

  def destroy_account
    user = current_api_user
    # Cancel active subscriptions
    user.subscriptions.where(active: true).each do |sub|
      sub.update(active: false, cancelling_at_end_of_billing_period: true)
    end
    # Soft-delete: archive and remove access
    user.update(approved: false, archived: true)
    render json: { success: true }
  end

  def usage
    user = current_api_user
    location = current_location
    now = Time.current
    period_start = now.beginning_of_month

    # Reservation minutes this month
    reservation_minutes = user.reservations.where(cancelled: false)
      .where("datetime_in >= ?", period_start)
      .sum(:minutes)

    # Check-in count this month
    checkin_count = user.try(:checkins)&.where("created_at >= ?", period_start)&.count || 0

    # Day pass count this month
    day_pass_count = user.day_passes.where("day >= ?", period_start.to_date).count

    # Total reservations this month
    reservation_count = user.reservations.where(cancelled: false)
      .where("datetime_in >= ?", period_start).count

    render json: {
      period: now.strftime("%B %Y"),
      reservation_minutes: reservation_minutes,
      reservation_count: reservation_count,
      checkin_count: checkin_count,
      day_pass_count: day_pass_count,
    }
  end

  def purchase_credits
    amount = params[:amount].to_i
    return render_error('Amount must be greater than 0') unless amount > 0

    location = current_location
    return render_error('Credits are not enabled') unless location.try(:credits_enabled?)

    result = Billing::Credits::PurchaseCredits.call(
      location: location,
      amount: amount,
      user: current_api_user,
    )

    if result.success?
      render json: {
        success: true,
        credit_balance: current_api_user.reload.credit_balance,
        amount_charged: amount * (location.credit_cost_in_cents || 0),
      }
    else
      render_error(result.message || 'Unable to purchase credits')
    end
  end

  def credit_info
    location = current_location
    render json: {
      credits_enabled: location.try(:credits_enabled?) || false,
      credit_balance: current_api_user.credit_balance,
      credit_cost_cents: location.try(:credit_cost_in_cents) || 0,
    }
  end

  def accept_terms
    current_api_user.update(terms_accepted_at: Time.current)
    render json: { success: true }
  end

  def update_email_preferences
    opt_in = params[:marketing_opt_in].to_s == 'true' || params[:marketing_opt_in] == true
    current_api_user.update(marketing_consent: opt_in)
    render json: { success: true, marketing_opt_in: opt_in }
  end

  def register_push_token
    platform = params[:platform]&.downcase
    token = params[:token]

    if platform == 'ios'
      current_api_user.update_column(:ios_token, token)
    elsif platform == 'android'
      current_api_user.update_column(:android_token, token)
    end

    render json: { success: true }
  end

  private

  def user_params
    params.require(:user).permit(:name, :phone, :bio, :linkedin, :twitter, :website, :preferred_room_id, :preferred_meeting_duration)
  end

  def location_features(user)
    loc = user.current_location || user.original_location
    return {} unless loc
    {
      rooms_enabled: loc.rooms_enabled?,
      door_integration_enabled: loc.door_integration_enabled?,
      events_enabled: loc.events_enabled?,
      bulletin_board_enabled: loc.bulletin_board_enabled?,
      credits_enabled: loc.credits_enabled?,
      offices_enabled: loc.offices_enabled?,
      day_passes_enabled: loc.day_passes_enabled?,
      announcements_enabled: loc.announcements_enabled?,
    }
  end
end

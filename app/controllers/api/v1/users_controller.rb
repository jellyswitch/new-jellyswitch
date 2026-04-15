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
      location: user.original_location&.name,
      operator: user.operator.name,
      has_profile_photo: user.has_profile_photo?,
      credit_balance: user.credit_balance,
      location_id: user.current_location_id || user.original_location_id,
      operator_subdomain: user.operator.subdomain,
      features: location_features(user),
      locations: user.operator.locations.map { |l| { id: l.id, name: l.name } },
      terms_accepted: user.terms_accepted_at.present?,
      has_terms_of_service: user.operator.terms_of_service.attached?,
      terms_of_service_url: user.operator.terms_of_service.attached? ? Rails.application.routes.url_helpers.rails_blob_url(user.operator.terms_of_service, only_path: false) : nil,
      preferred_room_id: user.preferred_room_id,
      preferred_meeting_duration: user.preferred_meeting_duration,
      marketing_opt_in: user.try(:marketing_opt_in),
      organization_id: user.try(:organization_id),
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
    opt_in = params[:marketing_opt_in]
    current_api_user.update(marketing_opt_in: opt_in)
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

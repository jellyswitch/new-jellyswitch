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
    }
  end

  def update
    if current_api_user.update(user_params)
      render json: { success: true }
    else
      render_error(current_api_user.errors.full_messages.first)
    end
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
end

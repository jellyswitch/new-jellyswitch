class Operator::UnsubscribesController < Operator::BaseController
  skip_before_action :require_complete_profile
  skip_before_action :set_navigation

  def show
    user_id = Rails.application.message_verifier(:unsubscribe).verify(params[:id])
    @user = User.find(user_id)
    @user.update_column(:email_opted_out, true)
    @operator = current_tenant
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    @error = true
  end
end

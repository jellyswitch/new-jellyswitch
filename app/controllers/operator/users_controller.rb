
class Operator::UsersController < Operator::BaseController
  include UsersHelper
  before_action :require_authentication, except: [:new, :create, :confirmation_pending]
  before_action :background_image

  def index
    @pagy, @users = find_approved_users
    @unapproved_users = find_unapproved_users
    @archived_users_count = User.for_space(current_tenant).archived.count
    authorize @users
  end

  def search
    @query = params[:query]
    @pagy, @users = find_approved_users(@query)
    @unapproved_users = find_unapproved_users
    @archived_users_count = User.for_space(current_tenant).archived.count
    authorize @users
    render :index
  end

  def unapproved
    set_unapproved_users
    authorize @users
  end

  def archived
    set_archived_users
    authorize @users
  end

  def search_archived
    @query = params[:query]
    @pagy, @users = find_archived_users_with_search(@query)
    authorize @users
    render :archived
  end

  def show
    find_user
    authorize @user

    @usage_report = Jellyswitch::UsageReport.new(@user)

    if @user == current_user
      render :show
    else
      render :profile
    end
  end

  def about
    find_user(:user_id)
    authorize @user
  end

  def ltv
    find_user(:user_id)
    authorize @user

    @months = (Time.current.year * 12 + Time.current.month) - (@user.created_at.year * 12 + @user.created_at.month)
  end

  def usage
    find_user(:user_id)
    authorize @user
    @usage_report = Jellyswitch::UsageReport.new(@user)
  end

  def payment_method
    find_user(:user_id)
    authorize @user
  end

  def membership
    find_user(:user_id)
    authorize @user
  end

  def admin_day_passes
    find_user(:user_id)
    authorize @user
  end

  def checkins
    find_user(:user_id)
    authorize @user
  end

  def organization
    find_user(:user_id)
    authorize @user
  end

  def admin_invoices
    find_user(:user_id)
    authorize @user
  end

  def new
    @user = User.new
    @include_recaptcha = true
    authorize @user

    if logged_in? && !current_user.admin_of_location?(current_location)
      # this is a normal user creating another user
      flash[:success] = "Please log out first."
      redirect_to root_path
    end
  end

  def add_member
    @user = User.new
    @user.approved = true
    authorize @user
  end

  def edit
    find_user
    authorize @user
  end

  def confirmation_pending
    @email = params[:email]
  end

  def create
    authorize User.new

    # Honeypot: if this hidden field is filled, it's a bot
    if params[:user][:website_url].present?
      # Silently redirect as if signup succeeded — don't tip off the bot
      turbo_redirect(confirmation_pending_users_path(email: params[:user][:email]), action: "replace")
      return
    end

    # reCAPTCHA v3: verify token for non-admin signups
    unless admin?
      if !verify_recaptcha(params[:user][:recaptcha_token])
        flash[:error] = "Signup could not be verified. Please try again."
        @user = User.new(user_params.except(:password, :password_confirmation))
        @include_recaptcha = true
        render :new, status: 422
        return
      end
    end

    is_admin = admin?
    result = Users::Create.call(params: user_params, operator: current_tenant, admin_created: is_admin)

    if result.success?
      if is_admin # admin is creating the user
        flash[:success] = "Member #{result.user.name} added."
        if params[:add_member_and_create_another].present?
          turbo_redirect(add_member_users_path, action: "replace")
        else
          turbo_redirect(user_path(result.user), action: "replace")
        end
      else
        # Redirect to confirmation pending page instead of logging in
        turbo_redirect(confirmation_pending_users_path(email: result.user.email), action: "replace")
      end
    else
      @user = result.user
      @include_recaptcha = true

      if admin? # Admin is creating a user
        render :add_member, status: 422
      else
        render :new, status: 422
      end
    end
  rescue Exception => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def update
    find_user
    authorize @user

    @user.update(user_params)

    # Set terms_accepted_at when user accepts terms on profile edit
    if params[:user][:terms_accepted] == "1" && @user.terms_accepted_at.blank?
      @user.terms_accepted_at = Time.current
    end

    if @user.save
      flash[:success] = "Your profile has been updated."
      turbo_redirect(user_path(@user))
    else
      render :edit, status: 422
    end
  rescue Exception => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def change_password
    find_user(:user_id)
    authorize @user
  end

  def update_password
    find_user(:user_id)
    authorize @user

    @user.update(user_password_params)

    if @user.save
      flash[:success] = "Your password has been changed."
      turbo_redirect(user_path(@user))
    else
      render :change_password, status: 422
    end
  rescue Exception => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def update_organization
    find_user(:user_id)
    authorize @user

    @user.update(user_organization_params)

    if @user.save
      flash[:success] = "Updated organization."
      turbo_redirect(user_path(@user))
    else
      @usage_report = Jellyswitch::UsageReport.new(@user)
      render :show, status: 422
    end
  rescue Exception => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def remove_from_organization
    find_user(:user_id)
    authorize @user

    if @user.update_column(:organization_id, nil)
      flash[:success] = "Removed from group."
    else
      flash[:error] = "Unable to remove from group."
    end

    turbo_redirect(user_path(@user), action: "replace")
  end


  def memberships
    find_user(:user_id)
    authorize @user
  end

  def day_passes
    find_user(:user_id)
    authorize @user
  end

  def reservations
    find_user(:user_id)
    authorize @user

    find_upcoming_reservations
  end

  def past_reservations
    find_user(:user_id)
    authorize @user

    find_past_reservations
  end

  def invoices
    find_user(:user_id)
    authorize @user

    @invoices = @user.invoices
  end

  def approve
    find_user(:user_id)
    @user.update_column(:approved, true)

    # Auto-activate pending subscription if user already selected a plan
    pending_sub = @user.subscriptions.pending.first
    if pending_sub
      location = @user.original_location || current_location
      result = Billing::Subscription::ActivatePendingSubscription.call(
        subscription: pending_sub,
        user: @user,
        operator: current_tenant,
        location: location,
        start_day: nil
      )
      if result.success?
        flash[:success] = "User approved and membership activated."
      else
        flash[:success] = "User approved. Membership activation failed: #{result.message}"
      end
    else
      flash[:success] = "User approved."
    end

    SendNotificationsJob.perform_later(@user, "Approval")
    turbo_redirect(approval_redirect_path)
  end

  def unapprove
    find_user(:user_id)
    @user.update_column(:approved, false)
    flash[:success] = "User unapproved."
    turbo_redirect(approval_redirect_path)
  end

  def archive
    find_user(:user_id)
    authorize @user

    if @user.member_at_operator?(current_tenant)
      flash[:error] = "Cannot archive an active member."
    else
      @user.update_columns(archived: true, approved: false)
      @user.feed_items.where("blob->>'type' = ?", "new-user").destroy_all
      flash[:success] = "User archived (and unapproved)."
    end
    turbo_redirect(user_path(@user))
  end

  def unarchive
    find_user(:user_id)
    authorize @user
    @user.update_columns(archived: false, approved: true)
    flash[:success] = "User unarchived."
    turbo_redirect(user_path(@user))
  end

  def edit_billing
    find_user(:user_id)
    include_stripe
  end

  def update_billing
    find_user(:user_id)
    token = params[:stripeToken]
    result = Billing::Payment::UpdateUserPayment.call(user: current_user, location: current_location, token: token)
    if result.success?
      flash[:success] = "Billing info updated."
      turbo_redirect(user_path(current_user))
    else
      flash[:error] = result.message
      turbo_redirect(user_billing_path(current_user))
    end
  end

  def update_payment_method
    find_user(:user_id)

    if payment_method_params[:out_of_band] == "1"
      result = MarkCustomerAsOutOfBand.call(user: @user)
    else
      result = UnmarkCustomerAsOutOfBand.call(user: @user)
    end

    if result.success?
      flash[:success] = "Payment method updated."
    else
      flash[:error] = result.message
    end

    turbo_redirect(user_path(@user))
  end

  def credit_card
    find_user(:user_id)
    result = Billing::Payment::SetToCreditCard.call(user: @user, location: current_location)

    if result.success?
      flash[:success] = "Payment method updated."
    else
      flash[:error] = result.message
    end

    turbo_redirect(user_path(@user), action: "replace")
  end

  def credits
    find_user(:user_id)
    authorize @user
  end

  def childcare
    find_user(:user_id)
    authorize @user
  end

  def add_credits
    find_user(:user_id)
    authorize @user

    result = Users::AddCredits.call(
      user: @user,
      amount: params[:amount].to_i
    )

    if result.success?
      flash[:success] = "Credits added."
    else
      flash[:error] = result.message
    end

    turbo_redirect(user_credits_path(@user), action: "replace")
  end

  def add_childcare_reservations
    find_user(:user_id)
    authorize @user

    result = Users::AddChildcareReservations.call(
      user: @user,
      amount: params[:amount].to_i
    )

    if result.success?
      flash[:success] = "Balance added."
    else
      flash[:error] = result.message
    end

    turbo_redirect(user_childcare_path(@user), action: "replace")
  end

  def out_of_band
    find_user(:user_id)
    result = Billing::Payment::SetToOutOfBand.call(user: @user, location: current_location)

    if result.success?
      flash[:success] = "Payment method updated."
    else
      flash[:error] = result.message
    end

    turbo_redirect(user_path(@user), action: "replace")
  end

  def bill_to_organization
    find_user(:user_id)
    result = Billing::Payment::SetToBillOrganization.call(user: @user)

    if result.success?
      flash[:success] = "Payment method updated."
    else
      flash[:error] = result.message
    end

    turbo_redirect(user_path(@user), action: "replace")
  end

  def destroy
    find_user

    if @user.organization_owner?
      flash[:error] = "You must leave the following group prior to account deletion: #{@user.owned_organization.name}"
      turbo_redirect(referrer_or_root)
      return
    end

    begin
      UserManager.new(user: @user).ready
      flash[:success] = "User account deleted"
      log_out
      turbo_redirect(signup_path)
    rescue Exception => e
      flash[:error] = "Something went wrong: #{e.message}"
      turbo_redirect(referrer_or_root)
    end
  end

  def change_account
    find_user(:user_id)
    if current_user.subscriptions.active.first
      @subscription = Subscription.find(current_user.subscriptions.active.first.id)
    end
  end

  def toggle_email_preferences
    type = params[:type]
    if type == "marketing"
      current_user.update!(email_opted_out: !current_user.email_opted_out?)
      status = current_user.email_opted_out? ? "unsubscribed from" : "subscribed to"
      flash[:notice] = "You've been #{status} marketing emails."
    end
    turbo_redirect(user_path(current_user))
  end

  private

  def verify_recaptcha(token)
    return true if ENV["RECAPTCHA_SECRET_KEY"].blank? # Skip if not configured
    return false if token.blank?

    response = HTTParty.post("https://www.google.com/recaptcha/api/siteverify", body: {
      secret: ENV["RECAPTCHA_SECRET_KEY"],
      response: token
    })

    result = JSON.parse(response.body)
    result["success"] && result["score"].to_f >= 0.5
  rescue StandardError => e
    Rails.logger.error("reCAPTCHA verification failed: #{e.message}")
    true # Allow signup if reCAPTCHA service is down — don't block real users
  end

  def user_password_params
    params.require(:user).permit(:password, :password_confirmation)
  end

  def user_organization_params
    params.require(:user).permit(:organization_id)
  end

  def payment_method_params
    params.require(:user).permit(:out_of_band)
  end

  def find_upcoming_reservations
    @reservations = @user.reservations.for_location_id(current_location&.id).future.order("datetime_in ASC").limit(100).group_by_day(&:datetime_in)
    @reservations.keys.each do |key|
      @reservations[key] = @reservations[key].map(&:decorate)
    end
  end

  def find_past_reservations
    @reservations = @user.reservations.for_location_id(current_location&.id).past.order("datetime_in ASC").limit(100).group_by_day(reverse: true) {|r| r.datetime_in }
    @reservations.keys.each do |key|
      @reservations[key] = @reservations[key].map(&:decorate)
    end
  end
end

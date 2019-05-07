class Operator::UsersController < Operator::BaseController
  def index
    find_approved_users
    @unapproved_users = User.for_space(current_tenant).unapproved
    authorize @users
    background_image
  end

  def unapproved
    find_unapproved_users
    authorize @users
    background_image
  end

  def show
    find_user
    authorize @user
    background_image

    if @user == current_user
      render :show
    else
      render :profile
    end
  end

  def new
    @user = User.new
    authorize @user

    if logged_in? && !admin?
      # this is a normal user creating another user
      flash[:success] = "Please log out first."
      redirect_to root_path
    end
    background_image
  end

  def add_member
    @user = User.new
    @user.approved = true
    authorize @user
    background_image
  end

  def edit
    find_user
    authorize @user
    background_image
  end

  def create
    authorize User.new
    result = CreateUser.call(params: user_params, operator: current_tenant)

    if result.success?
      if admin? # admin is creating the user
        flash[:success] = "Member #{result.user.name} added."
        if params[:add_member_and_create_another].present?
          turbolinks_redirect(add_member_users_path, action: "replace")
        else
          turbolinks_redirect(user_path(result.user), action: "replace")
        end
      else
        log_in(result.user)
        turbolinks_redirect(home_path, action: "replace")
      end
    else
      @user = result.user
      background_image
      if result.message
        flash[:error] = result.message
      end
      if admin? # Admin is creating a user
        render :add_member, status: 422
      else
        render :new, status: 422
      end
    end
  rescue Exception => e
    Rollbar.error(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbolinks_redirect(referrer_or_root)
  end

  def update
    find_user
    authorize @user

    @user.update_attributes(user_params)

    if @user.save
      flash[:success] = "Your profile has been updated."
      turbolinks_redirect(user_path(@user))
    else
      render :edit, status: 422
    end
  rescue Exception => e
    Rollbar.error(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbolinks_redirect(referrer_or_root)
  end

  def change_password
    find_user(:user_id)
    authorize @user
  end

  def update_password
    find_user(:user_id)
    authorize @user

    @user.update_attributes(user_password_params)

    if @user.save
      flash[:success] = "Your password has been changed."
      turbolinks_redirect(user_path(@user))
    else
      render :change_password, status: 422
    end
  rescue Exception => e
    Rollbar.error(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbolinks_redirect(referrer_or_root)
  end

  def update_organization
    find_user(:user_id)
    authorize @user

    @user.update_attributes(user_organization_params)

    if @user.save
      flash[:success] = "Updated organization."
      turbolinks_redirect(user_path(@user))
    else
      render :show, status: 422
    end
  rescue Exception => e
    Rollbar.error(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbolinks_redirect(referrer_or_root)
  end

  def memberships
    find_user(:user_id)
    authorize @user
    background_image
  end

  def day_passes
    find_user(:user_id)
    authorize @user
    background_image
  end

  def reservations
    find_user(:user_id)
    authorize @user

    @reservations = @user.reservations.order('created_at DESC').all.decorate
    background_image
  end

  def invoices
    find_user(:user_id)
    authorize @user

    @invoices = @user.invoices
    background_image
  end

  def approve
    find_user(:user_id)
    @user.update_attributes(user_approval_params)
    if @user.save
      flash[:success] = "User approved."
    else
      flash[:error] = "Couldn't approve user."
    end
    turbolinks_redirect(approval_redirect_path)
  end

  def unapprove
    find_user(:user_id)
    @user.update_attributes(user_approval_params)
    if @user.save
      flash[:success] = "User unapproved."
    else
      flash[:error] = "Couldn't unapprove user."
    end
    turbolinks_redirect(approval_redirect_path)
  end

  def edit_billing
    find_user(:user_id)
    background_image
    include_stripe
  end

  def update_billing
    find_user(:user_id)
    token = params[:stripeToken]
    result = Billing::Payment::UpdateUserPayment.call(user: current_user, token: token)
    if result.success?
      flash[:success] = "Billing info updated."
      turbolinks_redirect(user_path(current_user))
    else
      flash[:error] = result.message
      turbolinks_redirect(user_billing_path(current_user))
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

    turbolinks_redirect(user_path(@user))
  end

  private

  def user_params
    result = params.require(:user).permit(
      :name, :email, :password, :password_confirmation,
      :bio, :linkedin, :twitter, :website, :profile_photo,
      :approved, :admin, :add_member, :add_member_and_create_another,
      :always_allow_building_access)
    result
  end

  def user_password_params
    params.require(:user).permit(:password, :password_confirmation)
  end

  def user_organization_params
    params.require(:user).permit(:organization_id)
  end

  def user_approval_params
    params.require(:user).permit(:approved)
  end

  def payment_method_params
    params.require(:user).permit(:out_of_band)
  end

  def admin_hook
    if User.count < 1
      @user.admin = true
    end
  end

  def find_user(key=:id)
    @user = User.friendly.find(params[key])
  end

  def find_approved_users
    @users = User.for_space(current_tenant).approved
  end

  def find_unapproved_users
    @users = User.for_space(current_tenant).unapproved
  end

  def approval_redirect_path
    if params[:feed_item]
      feed_item = FeedItem.find params[:feed_item]
      feed_item_path(feed_item)
    else
      user_path(@user)
    end
  end
end

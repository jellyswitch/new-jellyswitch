class Operator::UsersController < Operator::ApplicationController
  def index
    find_approved_users
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
    @user = User.new(user_params)
    if !current_tenant.approval_required
      @user.approved = true
    end
    @user.operator = current_tenant
    authorize @user

    if @user.save
      if admin? # Admin is creating a user
        redirect_to user_path(@user)
      else
        log_in(@user)
        redirect_to home_path
      end
    else
      background_image
      if admin? # Admin is creating a user
        render :add_member, status: 422
      else
        render :new, status: 422
      end
    end
  end

  def update
    find_user
    authorize @user

    @user.update_attributes(user_params)

    if @user.save
      flash[:success] = "Your profile has been updated."
      redirect_to user_path(@user)
    else
      render :edit, status: 422
    end
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
      redirect_to user_path(@user)
    else
      render :change_password, status: 422
    end
  end

  def update_organization
    find_user(:user_id)
    authorize @user

    @user.update_attributes(user_organization_params)

    if @user.save
      flash[:success] = "Updated organization."
      redirect_to user_path(@user)
    else
      render :show, status: 422
    end
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
    redirect_to user_path(@user)
  end

  def unapprove
    find_user(:user_id)
    @user.update_attributes(user_approval_params)
    if @user.save
      flash[:success] = "User unapproved."
    else
      flash[:error] = "Couldn't unapprove user."
    end
    redirect_to user_path(@user)
  end

  def edit_billing
    find_user(:user_id)
    background_image
    include_stripe
  end

  def update_billing
    find_user(:user_id)
    token = params[:stripeToken]
    result = UpdateCustomerBillingInfo.call(user: current_user, token: token)
    if result.success?
      flash[:success] = "Billing info updated."
      redirect_to user_path(current_user)
    else
      flash[:error] = result.message
      redirect_to user_billing_path(current_user)
    end
  end

  private

  def user_params
    result = params.require(:user).permit(
      :name, :email, :password, :password_confirmation, 
      :bio, :linkedin, :twitter, :website, :profile_photo,
      :approved)
    result[:admin] = @user.admin if @user.present?
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
end

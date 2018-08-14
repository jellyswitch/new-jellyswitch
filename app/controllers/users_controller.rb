class UsersController < ApplicationController
  before_action :ensure_subscribed, except: [:new, :create]

  def index
    find_users
    authorize @users
    background_image
  end

  def show
    find_user
    authorize @user

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
      flash[:notice] = "Please log out first."
      redirect_to root_path
    end
    background_image
  end

  def add_member
    @user = User.new
    authorize @user
  end

  def edit
    find_user
    authorize @user
  end

  def create
    @user = User.new(user_params)
    authorize @user

    if @user.save
      log_in(@user)
      redirect_to home_path
    else
      background_image
      render :new
    end
  end

  def update
    find_user
    authorize @user

    @user.update_attributes(user_params)

    if @user.save
      flash[:notice] = "Your profile has been updated."
      redirect_to user_path(@user)
    else
      render :edit
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
      flash[:notice] = "Your password has been changed."
      redirect_to user_path(@user)
    else
      render :change_password
    end
  end

  def update_organization
    find_user(:user_id)
    authorize @user

    @user.update_attributes(user_organization_params)

    if @user.save
      flash[:notice] = "Updated organization."
      redirect_to user_path(@user)
    else
      render :show
    end
  end

  private

  def user_params
    result = params.require(:user).permit(:name, :email, :password, :password_confirmation, :bio, :linkedin, :twitter, :website, :profile_photo)
    result[:admin] = @user.admin if @user.present?
    result
  end

  def user_password_params
    params.require(:user).permit(:password, :password_confirmation)
  end

  def user_organization_params
    params.require(:user).permit(:organization_id)
  end

  def 

  def admin_hook
    if User.count < 1
      @user.admin = true
    end
  end

  def find_user(key=:id)
    @user = User.friendly.find(params[key])
  end

  def find_users
    @users = User
  end
end

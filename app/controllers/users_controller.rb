class UsersController < ApplicationController
  before_action :authenticate!, except: [:new, :create]

  def index
    find_users
  end

  def show
    find_user

    if @user == current_user
      render :show
    else
      render :profile
    end
  end

  def new
    @user = User.new
  end

  def edit
    find_user
  end

  def create
    @user = User.new(user_params)

    if @user.save
      log_in(@user)
      redirect_to root_path
    else
      render :new
    end
  end

  def update
    find_user

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
  end

  def update_password
    find_user(:user_id)

    @user.update_attributes(user_password_params)
    
    if @user.save
      flash[:notice] = "Your password has been changed."
      redirect_to user_path(@user)
    else
      render :change_password
    end
  end

  private

  def user_params
    result = params.require(:user).permit(:name, :email, :password, :password_confirmation, :bio, :linkedin, :twitter, :website)
    result[:admin] = @user.admin
    result
  end

  def user_password_params
    params.require(:user).permit(:password, :password_confirmation)
  end

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

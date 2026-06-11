
class SessionsController < ApplicationController
  def new
    authorize :session, :new?
  end

  def create
    authorize :session, :create?

    # Bots/scanners POST to /login with no (or an empty) `session` param,
    # which Rails drops entirely — guard so we redirect instead of 500ing on nil.
    if params[:session].blank?
      flash[:error] = "Please enter your email and password."
      turbo_redirect(operator_login_path, action: "replace")
      return
    end

    users = User.where(email: params[:session][:email].downcase, admin: true)

    if users.count < 1
      flash[:error] = "No such user found."
      turbo_redirect(operator_login_path)
    elsif users.count == 1
      if users.first.superadmin?
        # redirect to password form
        session[:email] = users.first.email
        turbo_redirect(password_form_path)
      else
        turbo_redirect( landing_url(subdomain: users.first.operator.subdomain) )
      end
    else
      # redirect to choose_operator
      session[:email] = params[:session][:email].downcase
      turbo_redirect(choose_operator_path)
    end
  end

  def choose_operator
    email = session[:email]
    users = User.where(email: email, superadmin: false, admin: true)
    @operators = users.collect(&:operator).uniq.compact
  end

  def password_form
    email = session[:email]
    
    @user = User.find_by(email: email, superadmin: true)
    if @user.blank?
      flash[:error] = "No such user."
      turbo_redirect(operator_login_path)
    end
  end

  def real_create
    # for admins only

    # Same nil-param guard as `create` — a POST to /real_login with no
    # `session` param would otherwise raise on `params[:session][:email]`.
    if params[:session].blank?
      flash[:error] = "Please enter your email and password."
      turbo_redirect(password_form_path, action: "replace")
      return
    end

    user = User.find_by(email: params[:session][:email].downcase, superadmin: true)
    if user && user.authenticate(params[:session][:password])
      log_in(user)
      remember(user)
      redirect_to operators_path
    else
      flash[:error] = "Invalid email/password combination."
      turbo_redirect(password_form_path)
    end
  end

  def destroy
    log_out
    turbo_redirect(root_path, action: restore_if_possible)
  end
end

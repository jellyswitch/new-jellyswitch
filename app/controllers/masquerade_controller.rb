class MasqueradeController < Operator::BaseController

  # current_masquerading_path
  def show
    session
  end

  # new_masquerade_path
  def new
    @users = find_regular_users
  end

  def update
    session
    @as_user = User.for_space(current_tenant).members.find(params[:user_id])
    masquerade_as(@as_user)
    redirect_to current_masquerading_path
  end

  def destroy
    session
    stop_masquerading
    redirect_to current_masquerading_path
  end

  private

  def find_regular_users
    User.for_space(current_tenant).approved.members.visible.order(updated_at: :desc, name: :asc)
  end

  def masquerade_as(user, location=nil)
    raise("Cannot masquerade as admin user") if user.admin?
    raise("Only admin users are allowed to masquerade") if !current_user.admin?
    raise("Admin cannot masquerade as users from other location") if (current_user.admin? && !user.manages_location?(user.original_location))
    # store the original admin user's session details
    session[:masquerade_by_user_id] = current_user.id
    session[:masquerade_original_location] = current_location.id
    # switch session details to begin masquerading
    session[:user_id] = user.id
    ahoy.authenticate user
    session[:location_id] = location.id if location
    it = { "user_id" => session[:user_id], "by_user_id" => session[:masquerade_by_user_id] }
    Rails.logger.error it.inspect
    remember(user)
  end

  def stop_masquerading
    raise("Not currently masquerading") if session[:masquerade_by_user_id].nil?
    raise("Only admin users are allowed to masquerade") if !current_user.admin?
    session[:user_id] = session[:masquerade_by_user_id]
    ahoy.authenticate User.find(session[:user_id].to_i)
    session[:location_id] = session[:masquerade_original_location]
  end
end

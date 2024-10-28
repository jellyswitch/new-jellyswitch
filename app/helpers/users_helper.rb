module UsersHelper
  def user_params
    result = params.require(:user).permit(
      :name, :email, :phone, :password, :password_confirmation,
      :bio, :linkedin, :twitter, :website, :profile_photo,
      :approved, :admin, :add_member, :add_member_and_create_another,
      :always_allow_building_access, :role, :original_location_id, :current_location_id
    )
    result
  end

  def find_user(key = :id)
    @user = User.friendly.find(params[key])
  end

  def find_approved_users(query = nil)
    if query.present?
      user_ids = User.search(query, fields: [:name, :email]).map(&:id)
      filtered_users = User.where(id: user_ids)
      pagy(filtered_users.for_space(current_tenant).approved.visible.order("name"))
    else
      pagy(User.for_space(current_tenant).approved.visible.order("name"))
    end
  end

  def find_unapproved_users
    @users = User.for_space(current_tenant).unapproved.visible.order("name")
  end

  def find_archived_users
    @pagy, @users = pagy(User.for_space(current_tenant).archived.order("name"))
  end

  def approval_redirect_path
    if params[:feed_item]
      feed_item = FeedItem.find params[:feed_item]
      feed_item_path(feed_item)
    else
      user_path(@user)
    end
  end

  def confirm_delete_message
    "Are you sure you want to delete your account?\nAny active memberships and any future reservations will be immediately cancelled.\nThis action cannot be reversed!\nIf you wish to rejoin at a later date, you will need to create a new account."
  end
end

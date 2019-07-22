module UsersHelper
  def user_params
    result = params.require(:user).permit(
      :name, :email, :password, :password_confirmation,
      :bio, :linkedin, :twitter, :website, :profile_photo,
      :approved, :admin, :add_member, :add_member_and_create_another,
      :always_allow_building_access
    )
    result
  end
end
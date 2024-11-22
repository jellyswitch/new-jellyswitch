class NavigationFactory
  def self.for(logged_in, current_tenant, current_location, current_user)
    if logged_in
      if current_user.admin_of_location?(current_location) || current_user.superadmin?
        Navigation::Admin
      elsif current_user.community_manager_of_location?(current_location)
        Navigation::CommunityManager
      elsif current_user.general_manager_of_location?(current_location)
        Navigation::GeneralManager
      else
        Navigation::Member
      end
    else
      Navigation::LoggedOut
    end.new(current_tenant, current_location, current_user)
  end
end
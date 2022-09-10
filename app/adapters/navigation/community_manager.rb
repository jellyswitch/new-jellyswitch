class Navigation::CommunityManager < Navigation::Default
  def web
    "layouts/admin_nav"
  end

  def paths
    community_manager_nav_items
  end

  def tab_paths
    community_manager_tab_paths
  end
end
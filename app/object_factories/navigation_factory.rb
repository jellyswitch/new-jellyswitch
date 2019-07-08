class NavigationFactory
  def self.for(logged_in, admin)
    if logged_in
      if admin
        "layouts/admin_nav"
      else
        "layouts/nav"
      end
    else
      "layouts/logged_out_nav"
    end
  end
end
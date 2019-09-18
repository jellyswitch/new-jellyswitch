class Navigation::Default < SimpleDelegator
  include Rails.application.routes.url_helpers
  attr_reader :operator, :location, :user

  def initialize(operator, location, user)
    @operator = operator
    @location = location
    @user = user
  end

  def mobile
    "layouts/mobile_nav"
  end

  def admin_nav_items
    items = [
      {title: "Home", path: feed_items_path},
      {title: "Building Access", path: doors_path},
      {title: "Announcements", path: announcements_path},
      {title: "What's Happening?", path: events_path},
      {title: "Members & Groups", path: members_groups_path},
      {title: "Offices & Leases", path: offices_leases_path},
      {title: "Rooms & Reservations", path: rooms_path},
      {title: "Plans & Day Passes", path: plans_day_passes_path},
      {title: "Invoices & Expenses", path: accounting_index_path},
      {title: "Data", path: reports_path},
      {title: "Customization", path: customization_path},
      {title: "My Account", path: user_path(user)},
      {title: "Member Dashboard", path: home_path}
    ]

    if operator.locations.count > 1
      items = items.insert(
        4,
        {title: "Change Location", path: edit_set_location_path}
      )
    end

    items
  end

  def member_nav_items
    items = [
      {title: "Home", path: home_path},
      {title: "What's Happening?", path: events_path}
    ]

    if location.rooms.visible.count > 0
      items << {title: "Reserve a room", path: rooms_path}
    end

    if location.doors.count > 0
      items << {title: "Building Access", path: keys_doors_path}
    end

    items << {title: "My Account", path: user_path(user)}

    if operator.locations.count > 1
      items = items << {title: "Change Location", path: edit_set_location_path}
    end

    items
  end

  def logged_out_nav_items
    items = []
    if @location.present?
      items << {title: "Sign Up", path: signup_path}
      items << {title: "Sign In", path: login_path}
    end

    if operator.locations.count > 1
      items = items << {title: "Change Location", path: edit_set_location_path}
    end

    items
  end

  def admin_tab_paths
    [
      {title: "Home", path: feed_items_path},
      {title: "Search", path: new_search_result_path}
    ]
  end

  def member_tab_paths
    items = [
      {title: "Home", path: home_path}
    ]

    if location.doors.count > 0
      items << {title: "Building Access", path: keys_doors_path}
    else
      if location.rooms.visible.count > 0
        items << {title: "Reserve a room", path: rooms_path}
      else
        items << {title: "My Account", path: user_path(user)}
      end
    end
    items
  end

  def logged_out_tab_paths
    [
      {title: "Sign Up", path: signup_path},
      {title: "Sign In", path: login_path}
    ]
  end

end
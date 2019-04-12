module ApplicationHelper
  include PlansHelper
  include LandingHelper
  include SubscriptionsHelper
  include Pagy::Frontend

  def pretty_datetime(input)
    input.strftime("%m/%d/%Y at %l:%M%P")
  end

  def google_map(center)
    key = ENV['GOOGLE_MAPS_API_KEY']
    "https://maps.googleapis.com/maps/api/staticmap?key=#{key}&markers=size:small%7Ccolor:red%7C#{center}&size=500x500&zoom=17"
  end

  def favicon(operator)
    if operator.logo_image.attached?
      url_for(operator.logo_image)
    else
      nil
    end
  end

  def basic_card
    render "layouts/basic_card" do
      yield
    end
  end

  def wide_card
    render "layouts/wide_card" do
      yield
    end
  end

  def feed_item_card
    render "operator/feed_items/feed_item_card" do
      yield
    end
  end

  def title(page_title)
    content_for(:title) { page_title }
    page_title
  end

  def stripe_oauth_url(operator)
    client_id = ENV['STRIPE_CLIENT_ID']
    redirect_uri = operator_operator_stripe_connect_setup_url(operator, subdomain: operator.subdomain)
    "https://connect.stripe.com/oauth/authorize?response_type=code&client_id=#{client_id}&scope=read_write&redirect_uri=#{redirect_uri}"
  end

  def mobile_app_request?
    ios_request? || android_request?
  end

  def ios_request?
    request.env['HTTP_USER_AGENT'].match /(Jellyswitch)/ && !request.env['HTTP_USER_AGENT'].match(/Android/)
  end

  def android_request?
    request.env['HTTP_USER_AGENT'].match /(Jellyswitch\/Android)/
  end

  def admin_nav_items
    [
      {title: "Home", path: feed_items_path},
      {title: "Search", path: new_search_result_path},
      {title: "Members & Resources", path: members_resources_path},
      {title: "Finances", path: accounting_index_path},
      {title: "#{current_tenant.name} Settings", path: operator_path(current_tenant, subdomain: current_tenant.subdomain)},
      {title: "My Account", path: user_path(current_user)},
      {title: "My Membership", path: user_memberships_path(current_user)},
      {title: "My Day Passes", path: user_day_passes_path(current_user)},
      {title: "My Reservations", path: user_reservations_path(current_user)},
      {title: "My Invoices", path: user_invoices_path(current_user)},
      {title: "Change Password", path: user_change_password_path(current_user)},
      {title: "Member Dashboard", path: home_path},
      {title: "Office Spaces", path: offices_path}
    ]
  end

  def member_nav_items
    [
      {title: "Home", path: home_path},
      {title: "Reserve a room", path: rooms_path},
      {title: "Building Access", path: keys_doors_path},
      {title: "My Account", path: user_path(current_user)},
      {title: "My Membership", path: user_memberships_path(current_user)},
      {title: "My Day Passes", path: user_day_passes_path(current_user)},
      {title: "My Reservations", path: user_reservations_path(current_user)},
      {title: "My Invoices", path: user_invoices_path(current_user)},
      {title: "Change Password", path: user_change_password_path(current_user)}
    ]
  end

  def logged_out_nav_items
    [
      {title: "Sign Up", path: signup_path},
      {title: "Log In", path: login_path},
      {title: "Office Spaces", path: offices_path}
    ]
  end

  def days_option_for_current_month
    [*0..30].map do |i|
      day = Time.zone.now + i.days
      [day.to_formatted_s(:long), day.to_i]
    end
  end
end

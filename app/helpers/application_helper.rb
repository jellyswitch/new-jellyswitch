module ApplicationHelper
  include ChildcareHelper
  include CreditHelper
  include ErrorsHelper
  include LandingHelper
  include LayoutHelper
  include PlansHelper
  include WeeklyUpdateHelper

  include Pagy::Frontend

  def pretty_datetime(input)
    input.strftime("%m/%d/%Y at %l:%M%P")
  end

  def short_date(date)
    date.strftime("%m/%d/%Y")
  end

  def pretty_time(time)
    time.strftime("%l:%M%P")
  end

  def long_date(date)
    date.strftime("%B %e, %Y")
  end

  def pretty_timestamps(a, b)
    "#{pretty_time(a)} - #{pretty_time(b)}"
  end

  def pretty_dates(a, b)
    "#{long_date(a)} - #{long_date(b)}"
  end

  def human_time_from_now(date)
    if date == Time.zone.today
      "Today"
    elsif date == Time.zone.tomorrow
      "Tomorrow"
    elsif date == Time.zone.yesterday
      "Yesterday"
    else
      date.strftime("%A")
    end
  end

  def pretty_price(office_lease)
    if office_lease.subscription.present? &&
       office_lease.subscription.plan.present?
      office_lease.subscription.plan.pretty_price
    else
      nil
    end
  end

  def brand_color(operator)
    return "#007bff" unless operator.respond_to?(:subdomain)
    case operator.subdomain
    when "tml"                    then "#76B82A"  # Cowork Tahoe green
    when "untethered"             then "#1B3A4B"  # Untethered Space navy
    when "choosefolsomworkspace"  then "#4A5568"  # Choose Folsom slate
    when "studio"                 then "#8B2252"  # The Studio burgundy
    else
      # Self-serve brands set their own color during onboarding. Normalize to a
      # leading "#" so the CSS var and brand_color_hover's hex slicing stay valid
      # (the model allows the hex with or without a leading "#").
      color = operator.try(:primary_color).to_s.strip
      color.present? ? (color.start_with?("#") ? color : "##{color}") : "#007bff"
    end
  end

  def brand_color_hover(operator)
    # Darken the brand color slightly for hover states
    color = brand_color(operator)
    # Simple darkening: reduce each hex component by ~15%
    r = [(color[1..2].to_i(16) * 0.85).to_i, 0].max
    g = [(color[3..4].to_i(16) * 0.85).to_i, 0].max
    b = [(color[5..6].to_i(16) * 0.85).to_i, 0].max
    "#%02x%02x%02x" % [r, g, b]
  end

  def favicon(operator)
    icon = operator.icon_image
    url_for(icon) if icon.attached?
  end

  def stripe_oauth_url(operator, options = {})
    client_id = ENV["STRIPE_CLIENT_ID"] # the Jellyswitch SaaS Account ID
    redirect_uri = stripe_connect_setup_url # landing#stripe_connect_setup at https://.../stripe_connect_setup
    stripe_landing = options[:stripe_landing] || "login"
    "https://connect.stripe.com/oauth/authorize?response_type=code&client_id=#{client_id}&scope=read_write&redirect_uri=#{redirect_uri}&stripe_landing=#{stripe_landing}&state=#{options[:state]}"
  end

  def mobile_app_request?
    ios_request? || android_request? || old_android_request?
  end

  def user_agent
    request.env["HTTP_USER_AGENT"]
  end

  def has_user_agent?
    user_agent.present?
  end

  def untethered_ios_request?
    request.user_agent =~ /JellyswitchiOS/i
  end

  def ios_request?
    has_user_agent? && user_agent.match(/(Jellyswitch)/).present? && !old_android_request? && !android_request?
  end

  def android_request?
    has_user_agent? && user_agent.match(/(Jellyswitch\/Android\/1\.2)/).present?
  end

  def old_android_request?
    has_user_agent? && user_agent.match(/(Jellyswitch\/Android)/).present?
  end

  def mobile_app_request?
    ios_request? || android_request? || old_android_request?
  end

  def days_option_for_current_month
    [*0..30].map do |i|
      day = Time.zone.now + i.days
      [long_date(day), day.to_i]
    end
  end

  def restore_if_possible
    if ios_request? || android_request?
      "restore"
    else
      "replace"
    end
  end

  def format_working_hours(location, separator = "through")
    start = Time.strptime(location.working_day_start, "%R").strftime("%l:%M %P")
    ending = Time.strptime(location.working_day_end, "%R").strftime("%l:%M %P")
    "#{start} #{separator} #{ending}"
  end

  def active_working_hours?(location)
    config = working_hours_config(location)
    return false if config.blank?

    WorkingHours::Config.with_config(working_hours: config, holidays: [], time_zone: Time.zone.name) do
      Time.current.in_working_hours?
    end
  rescue WorkingHours::InvalidConfiguration => e
    # This drives a display-only "open now?" indicator — it must never take down
    # the page. Bad hours data (e.g. legacy un-padded "5:00") degrades to "closed".
    Rails.logger.warn("active_working_hours? skipped invalid config for location=#{location.try(:id)}: #{e.message}")
    false
  end

  def has_building_access?(user)
    if (!user)
      return false
    else
      user.has_building_access?(current_location)
    end
  end

  def boolean_to_yesno(value)
    if value
      "Yes"
    else
      "No"
    end
  end

  def quantize(collection, string)
    if collection.respond_to? :each
      count = collection.count
    else
      count = collection
    end

    if count <= 0
      string.pluralize
    elsif count == 1
      string.singularize
    else
      string.pluralize
    end
  end

  def membership_text(plan)
    if plan.operator.membership_text.present?
      "Memberships start at #{display_price(plan)} and include #{plan.operator.membership_text}."
    else
      "Memberships start at #{display_price(plan)} and vary from flexible desk space to full private offices."
    end
  end

  def working_hours_options
    [:open_sunday, :open_monday, :open_tuesday, :open_wednesday, :open_thursday, :open_friday, :open_saturday]
  end

  def no_cache
    render "layouts/no_cache"
  end

  def hourly_rate(loc)
    rate = number_to_currency(dollar_amount(loc.hourly_rate_in_cents))
    "#{rate} / hr"
  end

  def hourly_rate_room(room)
    rate = number_to_currency(dollar_amount(room.hourly_rate_in_cents))
    "#{rate} / hr"
  end

  def link_to_modal(id)
    render Bootstrap::LinkToModal.new(id: id) do
      yield
    end
  end

  def set_tracking_pixels
    return unless defined?(current_tenant) && current_tenant

    # Brand-global, not per-location: ad tags (Google Tag Manager, GA4) must
    # load on every page, including for logged-out visitors on multi-location
    # operators — there no current_location resolves, so per-location pixels
    # silently never injected. Rows still hang off a location (the settings UI
    # is location-tabbed), so the same snippet saved under several locations
    # dedupes to a single inject.
    pixels = TrackingPixel.where(operator: current_tenant).order(:id).to_a
    pixels.uniq! { |p| [p.position, p.script] }
    always_on, conversion_only = pixels.partition(&:always_on)

    # Always-on pixels (e.g. Google Tag Manager, Google Analytics) load on every page
    @head_pixels = always_on.select(&:head?)
    @body_pixels = always_on.select(&:body?)
    @footer_pixels = always_on.select(&:footer?)

    # Conversion-only pixels and the dataLayer purchase event fire once, on the
    # page rendered after a purchase (ApplicationController#track_conversion)
    if session[:should_track_pixels]
      # workaround for turbo redirect because it effectively renders twice
      if session[:first_pixel_render]
        @head_pixels += conversion_only.select(&:head?)
        @body_pixels += conversion_only.select(&:body?)
        @footer_pixels += conversion_only.select(&:footer?)
        @conversion_event = session.delete(:conversion_event)
        session.delete(:first_pixel_render)
        session.delete(:should_track_pixels)
      else
        session[:first_pixel_render] = true
      end
    end
  end

  private

  def working_hours_config(location)
    config = {}

    working_hours_options.map do |day|
      if location.send("#{day}?".to_sym) == true
        config[day.to_s.split("_").last.first(3).to_sym] = { location.working_day_start => location.working_day_end }
      end
    end
    config
  end
end

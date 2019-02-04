module ApplicationHelper
  include PlansHelper
  include LandingHelper
  include SubscriptionsHelper

  def pretty_datetime(input)
    input.strftime("%m/%d/%Y at %l:%M%P")
  end

  def google_map(center)
    key = ENV['GOOGLE_MAPS_API_KEY']
    "https://maps.googleapis.com/maps/api/staticmap?key=#{key}&markers=size:small%7Ccolor:red%7C#{center}&size=500x500&zoom=17"    
  end
end

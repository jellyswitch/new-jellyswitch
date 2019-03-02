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
end

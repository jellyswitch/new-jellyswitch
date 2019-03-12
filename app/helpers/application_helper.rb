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

  def stripe_oauth_url(operator)
    client_id = ENV['STRIPE_CLIENT_ID']
    redirect_uri = operator_operator_stripe_connect_setup_url(operator, subdomain: operator.subdomain)
    "https://connect.stripe.com/oauth/authorize?response_type=code&client_id=#{client_id}&scope=read_write&redirect_uri=#{redirect_uri}"
  end
end

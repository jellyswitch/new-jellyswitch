module ApplicationHelper
  include SessionsHelper
  include PlansHelper
  include LandingHelper
  include SubscriptionsHelper

  def pretty_datetime(input)
    input.strftime("%m/%d/%Y at %l:%M%P")
  end
end

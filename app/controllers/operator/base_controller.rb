class Operator::BaseController < ApplicationController
  set_current_tenant_by_subdomain(:operator, :subdomain)
  layout "operator"
  before_action :store_ios_token, if: :logged_in?

  def background_image
    @background_image = current_tenant.background_image if current_tenant.present?
  end

  def pundit_user
    UserContext.new(current_user, current_tenant)
  end

  def store_ios_token
    puts request.user_agent
    if logged_in?
      match = request.user_agent.match(/.*deviceToken: (.*)/)
      return if match.nil? || match[1].blank?
      token = match[1]
      current_user.update(ios_token: token)
    end
  end
end

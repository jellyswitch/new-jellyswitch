class Operator::BaseController < ApplicationController
  set_current_tenant_by_subdomain(:operator, :subdomain)
  layout "operator"
  before_action :store_ios_token, if: :logged_in?
  before_action :set_resource_scopes
  around_action :set_time_zone, if: :current_location

  def background_image
    @background_image = current_tenant.background_image if current_tenant.present?
  end

  def pundit_user
    UserContext.new(current_user, current_tenant, current_location)
  end

  def store_ios_token
    if logged_in?
      match = request.user_agent.match(/.*deviceToken: (.*)/)
      return if match.nil? || match[1].blank?
      token = match[1]
      current_user.update(ios_token: token)
    end
  end

  private

  def set_resource_scopes
    if ActsAsScopable.current_scope_resources.empty?
      ActsAsScopable.current_scope_resources = [current_tenant, current_location]
    end

    if current_tenant.blank?
      redirect_to status: 404
    end
  end

  def set_time_zone(&block)
    Time.use_zone(current_location.time_zone, &block)
  end
end

class Operator::BaseController < ApplicationController
  set_current_tenant_by_subdomain(:operator, :subdomain)
  layout "operator"

  def background_image
    @background_image = current_tenant.background_image
  end

  def pundit_user
    UserContext.new(current_user, current_tenant)
  end
end
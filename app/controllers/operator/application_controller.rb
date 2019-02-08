class Operator::ApplicationController < ::ApplicationController
  set_current_tenant_by_subdomain(:operator, :subdomain)
  layout "operator"

  def background_image
    @background_image = current_tenant.background
  end
end
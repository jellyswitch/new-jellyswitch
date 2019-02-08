class Operator::ApplicationController < ::ApplicationController
  set_current_tenant_by_subdomain(:operator, :subdomain)
  layout "operator"
end
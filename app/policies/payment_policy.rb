class PaymentPolicy < ApplicationPolicy
  include PolicyHelpers

  def enabled?
    operator.production? && operator.subdomain != "southlakecoworking"
  end
end
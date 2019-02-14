class InvoicePolicy < ApplicationPolicy
  include PolicyHelpers

  def index?
    admin?
  end
  
  def due?
    admin?
  end

  def recent?
    admin?
  end

  def delinquent?
    admin?
  end
end
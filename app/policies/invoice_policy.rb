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

  def charge?
    admin? && record.billable.card_added?
  end
end
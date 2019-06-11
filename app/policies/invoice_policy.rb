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
    admin? && card_added?
  end

  def groups?
    admin?
  end

  def open?
    admin?
  end

  private

  def card_added?
    case record.billable_type
    when "User"
      record.billable.card_added?
    when "Organization"
      record.billable.has_billing?
    end
  end
end
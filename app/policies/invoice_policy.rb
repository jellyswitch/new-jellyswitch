# typed: true
class InvoicePolicy < ApplicationPolicy
  include PolicyHelpers

  def index?
    (admin? || community_manager? || general_manager? && billing_enabled?)
  end
  
  def due?
    (admin? || community_manager? || general_manager? && billing_enabled?)
  end

  def recent?
    (admin? || community_manager? || general_manager? && billing_enabled?)
  end

  def delinquent?
    (admin? || community_manager? || general_manager? && billing_enabled?)
  end

  def charge?
    (admin? || general_manager? && card_added? && billing_enabled?)
  end

  def groups?
    (admin? || community_manager? || general_manager? && billing_enabled?)
  end

  def open?
    (admin? || community_manager? || general_manager? && billing_enabled?)
  end

  def new?
    (admin? || general_manager? && billing_enabled?)
  end

  def create?
    (admin? || general_manager? && billing_enabled?)
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
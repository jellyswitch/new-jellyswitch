class PaymentMethodComponent < ApplicationComponent
  def initialize(billable:)
    @billable = billable
  end

  private

  attr_reader :billable

  # When the billable is an Org with a billing_contact, charges actually
  # route to the contact (see OrganizationBillDecider). Display the card
  # that money will come out of, not the org's empty Stripe customer.
  def effective_billable
    if billable.is_a?(Organization) && billable.has_billing_contact?
      billable.billing_contact
    else
      billable
    end
  end

  def billing_via_contact?
    effective_billable != billable
  end

  def card_added_for_location?(location)
    effective_billable.card_added_for_location?(location)
  rescue StandardError
    false
  end

  def last_4_digits(location)
    effective_billable.card_last_4_digits(location) # XXX extract this into a concern on the user / organization model
  end

  def update_card_path
    if effective_billable.is_a?(User)
      user_billing_path(effective_billable)
    else
      organization_billing_path(effective_billable)
    end
  end

  def update_card_label
    if billing_via_contact?
      "Update #{effective_billable.name}'s card"
    else
      "Update credit card"
    end
  end

  def credit_card_path
    if user?
      user_credit_card_path(billable)
    else
      organization_credit_card_path(billable)
    end
  end

  def cash_or_check?
    billable.out_of_band?
  end

  def cash_or_check_path
    if user?
      user_out_of_band_path(billable)
    else
      organization_out_of_band_path(billable)
    end
  end

  def billable_to_group?
    user?
  end

  def bill_to_group?
    billable_to_group? && billable.bill_to_organization?
  end

  def member_of_group?
    billable_to_group? && billable.member_of_organization?
  end

  def bill_to_group_path
    if billable_to_group?
      user_bill_to_organization_path(billable)
    else
      raise "Cannot bill to group for a group."
    end
  end

  def group_name
    if user?
      billable.organization.name
    else
      billable.name
    end
  end

  def user?
    billable.class == User
  end

  def group?
    billable.class == Organization
  end
end
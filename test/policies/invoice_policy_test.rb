require "test_helper"

class InvoicePolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_index
    assert_not_permitted @member, Invoice
    assert_permit @admin, Invoice
    assert_permit @community_manager, Invoice
    assert_permit @general_manager, Invoice
  end

  def test_due
    assert_not_permitted @member, Invoice
    assert_permit @admin, Invoice
    assert_permit @community_manager, Invoice
    assert_permit @general_manager, Invoice
  end

  def test_recent
    assert_not_permitted @member, Invoice
    assert_permit @admin, Invoice
    assert_permit @community_manager, Invoice
    assert_permit @general_manager, Invoice
  end

  def test_delinquent
    assert_not_permitted @member, Invoice
    assert_permit @admin, Invoice
    assert_permit @community_manager, Invoice
    assert_permit @general_manager, Invoice
  end

  def test_charge
    assert_not_permitted @member, invoices(:member_invoice)
    assert_permit @admin, invoices(:member_invoice)
    assert_not_permitted @community_manager, invoices(:member_invoice)
    assert_permit @general_manager, invoices(:member_invoice)
  end

  def test_groups
    assert_not_permitted @member, Invoice
    assert_permit @admin, Invoice
    assert_permit @community_manager, Invoice
    assert_permit @general_manager, Invoice
  end

  def test_open
    assert_not_permitted @member, Invoice
    assert_permit @admin, Invoice
    assert_permit @community_manager, Invoice
    assert_permit @general_manager, Invoice
  end

  def test_new
    assert_not_permitted @member, Invoice
    assert_permit @admin, Invoice
    assert_not_permitted @community_manager, Invoice
    assert_permit @general_manager, Invoice
  end

  def test_create
    assert_not_permitted @member, Invoice
    assert_permit @admin, Invoice
    assert_not_permitted @community_manager, Invoice
    assert_permit @general_manager, Invoice
  end
end
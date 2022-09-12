require "test_helper"

class InvoicePolicyTest < PolicyAssertions::Test

  setup do
    @admin = UserContext.new(users(:cowork_tahoe_admin), operators(:cowork_tahoe), locations(:cowork_tahoe))
    @member = UserContext.new(users(:cowork_tahoe_member), operators(:cowork_tahoe), locations(:cowork_tahoe))
    @community_manager = UserContext.new(users(:cowork_tahoe_community_manager), operators(:cowork_tahoe), locations(:cowork_tahoe))
    @general_manager = UserContext.new(users(:cowork_tahoe_general_manager), operators(:cowork_tahoe), locations(:cowork_tahoe))
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
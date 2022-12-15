require "application_system_test_case"

class BillingContactTest < ApplicationSystemTestCase

  test 'if there is active subscription (from user set to bill_to_organization) admin sees disabled billing contact select form field' do
    @user = users(:cowork_tahoe_member)
    @user.update(bill_to_organization: true)
    StripeMock.start
    admin_user = users(:cowork_tahoe_admin)
    
    setup_stripe
    log_in(admin_user)
    assert_text "What's Happening?"

    visit edit_organization_url(organizations(:sierra_nevada_organization))
    assert_text "Edit Group"
    assert_text "If you wish to designate a billing contact, the following must first be cancelled:"
  end
  
  test 'if organization has no active subscriptions (or all users could be bill_to_organization: false) AND no active office leases, admin sees active billing contact select form field' do
    @user = users(:cowork_tahoe_member)
    @user.update(bill_to_organization: false)
    StripeMock.start
    admin_user = users(:cowork_tahoe_admin)
      
    setup_stripe

    log_in(admin_user)
    assert_text "What's Happening?"
    organization = organizations(:sierra_nevada_organization)
    organization.office_leases.first.update(end_date: Time.current - 1.day)

    visit edit_organization_url(organization)
    assert_text "Edit Group"
    assert_selector "strong", text: "If you wish to designate a billing contact, the following must first be cancelled:", count: 0
  end

  test 'if there is an active office_lease, admin sees disabled billing contact select form field' do
    @user = users(:cowork_tahoe_member)
    @user.update(bill_to_organization: false)
    StripeMock.start
    admin_user = users(:cowork_tahoe_admin)
    
    setup_stripe
    log_in(admin_user)
    assert_text "What's Happening?"
    organization = organizations(:sierra_nevada_organization)

    visit edit_organization_url(organization)
    assert_text "Edit Group"

    assert_text "If you wish to designate a billing contact, the following must first be cancelled:"
  end
end

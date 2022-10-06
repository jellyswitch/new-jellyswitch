require "application_system_test_case"

class PauseMembershipsTest < ApplicationSystemTestCase
  setup do
    StripeMock.start
  end
  
  test "user can see option to pause membership from change my account screen" do
    @user = users(:cowork_tahoe_member)
    setup_stripe
    log_in(@user)

    click_on 'My Account'
    assert_text "Change My Account"
    
    click_on 'Change My Account'
    assert_text "Pause Membership"
  end
  
  test "if paused, user can see option to reactivate membership from change my account screen" do
    @user = users(:cowork_tahoe_member)
    setup_stripe
    log_in(@user)

    click_on 'My Account'
    assert_text "Change My Account"
    
    click_on 'Change My Account'
    assert_text "Pause Membership"
    
    click_on 'Pause Membership'
    assert_text "You have paused your subscription"
    assert_text 'My Account'
    
    click_on 'My Account'
    assert_text "Change My Account"
    
    click_on 'Change My Account'
    assert_text "Reactivate Membership"
  end

  test "user can see option to pause membership from cancel membership modal" do
    @user = users(:cowork_tahoe_member)
    setup_stripe
    log_in(@user)

    click_on 'My Account'
    assert_text "View my membership"

    click_on "View my membership"
    assert_text "Cancel membership"

    click_on "Cancel membership"
    assert_text "Pause Membership"

    click_on "Pause Membership"
    assert_text "You have paused your subscription"
    assert_text "My Account"
  end

  # test "if paused, user can see option to reactivate membership from cancel membership modal" do
  #   @user = users(:cowork_tahoe_member)
  #   setup_stripe
  #   log_in(@user)

  #   click_on 'My Account'
  #   assert_text "View my membership"

  #   click_on "View my membership"
  #   assert_text "Cancel membership"

  #   click_on "Cancel membership"
  #   assert_text "Pause Membership"

  #   click_on "Pause Membership"
  #   assert_text "You have paused your subscription"
  #   assert_text "My Account"

  #   click_on 'My Account'
  #   assert_text "View my membership"

  #   click_on "View my membership"
  #   assert_text "Cancel membership"

  #   click_on "Cancel membership"
  #   assert_text "Reactivate Membership"
  # end
end
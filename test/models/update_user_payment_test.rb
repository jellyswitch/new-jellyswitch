require 'test_helper'

class Billing::Payment::UpdateUserPaymentTest < ActiveSupport::TestCase
  # setup do
  #   @user = users(:cowork_tahoe_member)

  #   StripeMock.start

  #   setup_stripe
  # end

  # teardown do
  #   StripeMock.stop
  # end
  
  # test "it updates user to out_of_band" do
  #   Billing::Payment::UpdateUserPayment.call(user: @user, token: token, out_of_band: true)

  #   assert @user.out_of_band?
  #   assert !@user.card_added?
  # end

  # test "it updates user to card_added" do
  #   Billing::Payment::UpdateUserPayment.call(user: @user, token: token)

  #   assert @user.card_added?
  #   assert !@user.out_of_band?
  # end
end
require 'test_helper'

class Billing::Credits::ResetTest < ActiveSupport::TestCase
  test "it resets the credit count upon cancellation" do
    @user = users(:cowork_tahoe_member)
    @user.update(credit_balance: 100)

    result = Billing::Credits::Reset.call(creditable: @user)

    assert result.success?
    assert @user.credit_balance == 0
  end
end
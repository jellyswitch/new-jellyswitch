require "test_helper"

class LocationSpaceHostTest < ActiveSupport::TestCase
  setup do
    @location = locations(:cowork_tahoe_location)
    @same_operator_user = users(:cowork_tahoe_admin)
  end

  test "accepts a user from the same operator" do
    @location.space_host_id = @same_operator_user.id
    assert @location.valid?, @location.errors.full_messages.to_sentence
  end

  test "accepts nil (the default fallback)" do
    @location.space_host_id = nil
    assert @location.valid?
  end

  test "rejects a user from a different operator" do
    other_operator = create(:operator)
    foreign_user = User.create!(
      name: "Foreign",
      email: "foreign-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      password_confirmation: "password",
      role: User::ADMIN,
      operator: other_operator,
      approved: true,
      email_confirmed: true,
      phone: "555-555-1234"
    )

    @location.space_host_id = foreign_user.id
    assert_not @location.valid?
    assert_includes @location.errors[:space_host_id], "must be a member of this operator"
  end
end

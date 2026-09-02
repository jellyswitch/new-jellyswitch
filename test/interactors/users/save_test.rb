require 'test_helper'

# Signing up with the email of a widget-created CRM stub completes that
# record instead of failing on the unique email (see Users::Save#claimable_stub).
class Users::SaveTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @operator.update!(approval_required: true)
    # Exactly what Embed::TourRequestsController / SisterSpaceMirror write.
    @stub = User.create!(
      email: "prospect@example.com", name: "Widget Name", operator: @operator,
      original_location_id: @location.id, admin_created: true, password: SecureRandom.hex(16),
    )
    @signup_activities_before = Activity.where(user: @stub, kind: "signup").count
  end

  def signup(overrides = {})
    Users::Create.call(
      params: {
        name: "Real Name", email: "Prospect@example.com", password: "password123",
        phone: "5305551234", original_location_id: @location.id, terms_accepted: "1",
      }.merge(overrides),
      operator: @operator, admin_created: false,
    )
  end

  test "signing up with a stub's email claims the stub instead of failing" do
    result = nil
    assert_no_difference -> { User.count } do
      result = signup
    end

    assert result.success?, result.message
    assert result.claimed
    assert_equal @stub.id, result.user.id

    @stub.reload
    assert_equal "Real Name", @stub.name
    assert_equal "5305551234", @stub.phone
    assert @stub.authenticate("password123")
    assert @stub.terms_accepted_at.present?
    refute @stub.email_confirmed?, "claim is a self-signup: confirmation still required"
    assert @stub.confirmation_token.present?
    # The stub's history is kept — no second signup Activity.
    assert_equal @signup_activities_before, Activity.where(user: @stub, kind: "signup").count
  end

  test "a claim sends the confirmation email like a fresh signup" do
    assert_emails 1 do
      perform_enqueued_jobs { signup }
    end
  end

  test "a claim still enforces the create-time rules" do
    result = signup(password: "123")
    refute result.success?
    assert_match(/Password/, result.message)
    assert @stub.reload.authenticate(nil).nil? || !@stub.authenticate("123")
  end

  test "a claim that dies at Stripe leaves the stub untouched and claimable" do
    Stripe::Customer.stubs(:create).raises(Stripe::InvalidRequestError.new("nope", "email"))
    result = signup
    refute result.success?

    @stub.reload
    assert_equal "Widget Name", @stub.name
    assert_nil @stub.terms_accepted_at
    assert User.exists?(@stub.id)
  end

  test "a confirmed account is never claimed" do
    @stub.update!(email_confirmed: true)
    result = signup
    refute result.success?
    assert_match(/already been taken/, result.message)
  end

  test "an approved account is never claimed" do
    @stub.update!(approved: true)
    refute signup.success?
  end

  test "an account that accepted terms is never claimed" do
    @stub.update!(terms_accepted_at: 1.day.ago)
    refute signup.success?
  end

  test "a staff account is never claimed" do
    @stub.update!(role: User::ADMIN)
    refute signup.success?
  end

  test "fresh signups are unaffected" do
    result = nil
    assert_difference -> { User.count }, 1 do
      result = signup(email: "brand-new@example.com")
    end
    assert result.success?, result.message
    refute result.claimed
  end
end

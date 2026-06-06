require "test_helper"

class Onboarding::Import::CommitTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member = users(:cowork_tahoe_member) # tim@jellyswitch.com
    @full_time_plan = plans(:cowork_tahoe_full_time_plan)
    @column_mapping = {
      email: "Email",
      name: "Name",
      phone: "Phone",
      company: "Company",
      stripe_customer_id: "Stripe Customer",
      membership: "Membership",
    }
    ActsAsTenant.current_tenant = @operator
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def commit(rows, plan_mapping: {})
    Onboarding::Import::Commit.call(
      location: @location,
      rows: rows,
      column_mapping: @column_mapping,
      plan_mapping: plan_mapping,
    )
  end

  test "fails without a location" do
    result = Onboarding::Import::Commit.call(location: nil, rows: [])
    assert result.failure?
  end

  test "creates a new user with a payment profile from a row" do
    rows = [{ "Name" => "Ada Import", "Email" => "ada-import@example.com",
              "Phone" => "555-1212", "Stripe Customer" => "cus_NEWADA1" }]

    assert_difference -> { @operator.users.count } => 1, -> { UserPaymentProfile.count } => 1 do
      result = commit(rows)
      assert result.success?, result.message
      assert_equal 1, result.report[:summary][:users_created]
      assert_equal 1, result.report[:summary][:payment_profiles_created]
    end

    user = @operator.users.find_by("lower(email) = ?", "ada-import@example.com")
    assert user.present?
    assert user.approved?
    profile = user.user_payment_profiles.find_by(location_id: @location.id)
    assert_equal "cus_NEWADA1", profile.stripe_customer_id
  end

  test "is idempotent — re-running does not duplicate" do
    rows = [{ "Name" => "Ada Import", "Email" => "ada-import@example.com",
              "Stripe Customer" => "cus_NEWADA1" }]
    commit(rows)

    assert_no_difference -> { @operator.users.count } do
      assert_no_difference -> { UserPaymentProfile.count } do
        result = commit(rows)
        assert result.success?
        assert_equal 0, result.report[:summary][:users_created]
      end
    end
  end

  test "matches an existing member by email instead of creating a duplicate" do
    rows = [{ "Name" => "Tim C", "Email" => "TIM@jellyswitch.com" }]

    assert_no_difference -> { @operator.users.count } do
      result = commit(rows)
      assert result.success?
      assert_equal :updated, result.report[:rows].first[:action]
    end
  end

  test "skips a row with no name" do
    rows = [{ "Name" => "", "Email" => "noname@example.com" }]

    assert_no_difference -> { @operator.users.count } do
      result = commit(rows)
      assert_equal :skipped, result.report[:rows].first[:action]
      assert_match(/name/i, result.report[:rows].first[:notes])
    end
  end

  test "skips a row with neither email nor stripe id" do
    rows = [{ "Name" => "Ghost", "Email" => "" }]
    result = commit(rows)
    assert_equal :skipped, result.report[:rows].first[:action]
  end

  test "creates an organization and links the user to it" do
    rows = [{ "Name" => "Org Person", "Email" => "orgperson@example.com", "Company" => "Acme Co" }]

    assert_difference -> { @operator.organizations.count } => 1 do
      result = commit(rows)
      assert result.success?
    end

    org = @operator.organizations.find_by("lower(name) = ?", "acme co")
    assert org.present?
    user = @operator.users.find_by("lower(email) = ?", "orgperson@example.com")
    assert_equal org.id, user.organization_id
  end

  test "creates a subscription when membership maps to a plan, idempotently" do
    rows = [{ "Name" => "Sub Person", "Email" => "subperson@example.com", "Membership" => "Full Time" }]
    mapping = { "Full Time" => @full_time_plan.id }

    assert_difference -> { Subscription.count } => 1 do
      result = commit(rows, plan_mapping: mapping)
      assert result.success?
      assert_equal 1, result.report[:summary][:subscriptions_created]
    end

    user = @operator.users.find_by("lower(email) = ?", "subperson@example.com")
    sub = Subscription.find_by(subscribable_type: "User", subscribable_id: user.id, plan_id: @full_time_plan.id)
    assert sub.active?

    # Second run must not create a duplicate subscription.
    assert_no_difference -> { Subscription.count } do
      result = commit(rows, plan_mapping: mapping)
      assert_includes result.report[:rows].first[:notes], "already present"
    end
  end

  test "records a note when membership is not mapped to any plan" do
    rows = [{ "Name" => "Unmapped", "Email" => "unmapped@example.com", "Membership" => "Mystery Tier" }]

    assert_no_difference -> { Subscription.count } do
      result = commit(rows)
      assert_match(/not mapped/i, result.report[:rows].first[:notes])
    end
  end
end

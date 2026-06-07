require "test_helper"

class Onboarding::Import::BuildPreviewTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member = users(:cowork_tahoe_member) # tim@jellyswitch.com
    @column_mapping = {
      email: "Email",
      name: "Name",
      stripe_customer_id: "Stripe Customer",
      membership: "Membership",
    }
  end

  def preview_for(rows, plan_mapping: {})
    ActsAsTenant.with_tenant(@operator) do
      Onboarding::Import::BuildPreview.call(
        location: @location,
        rows: rows,
        column_mapping: @column_mapping,
        plan_mapping: plan_mapping,
      )
    end
  end

  test "fails without a location" do
    result = Onboarding::Import::BuildPreview.call(location: nil, rows: [])
    assert result.failure?
  end

  test "matches an existing member by email, case-insensitively" do
    rows = [{ "Name" => "Tim C", "Email" => "TIM@jellyswitch.com" }]
    result = preview_for(rows)

    assert result.success?
    row = result.preview[:rows].first
    assert_equal :existing_email, row[:match_type]
    assert_equal @member.id, row[:matched_user_id]
    assert_equal 1, result.preview[:summary][:matched_existing]
  end

  test "matches an existing member by Stripe customer id" do
    rows = [{ "Name" => "Whoever", "Email" => "brand-new@example.com", "Stripe Customer" => "cus_MIxudSkB0PDeE5" }]
    result = preview_for(rows)

    row = result.preview[:rows].first
    assert_equal :existing_stripe, row[:match_type]
    assert_not_nil row[:matched_user_id]
  end

  test "flags a row with no email and no stripe id as an error" do
    rows = [{ "Name" => "No Identity", "Email" => "" }]
    result = preview_for(rows)

    row = result.preview[:rows].first
    assert_equal :new, row[:match_type]
    assert row[:error].present?
    assert_equal 1, result.preview[:summary][:errors]
  end

  test "treats an unknown email as a new member" do
    rows = [{ "Name" => "Newbie", "Email" => "newbie@example.com" }]
    result = preview_for(rows)

    row = result.preview[:rows].first
    assert_equal :new, row[:match_type]
    assert_nil row[:matched_user_id]
    assert_equal 1, result.preview[:summary][:new]
  end

  test "detects duplicate emails within the file" do
    rows = [
      { "Name" => "A", "Email" => "dup@example.com" },
      { "Name" => "B", "Email" => "dup@example.com" },
    ]
    result = preview_for(rows)

    assert_includes result.preview[:rows].last[:warnings], "duplicate email in file"
  end

  test "summarizes distinct membership values and their mapping status" do
    rows = [
      { "Name" => "A", "Email" => "a@example.com", "Membership" => "Full Time" },
      { "Name" => "B", "Email" => "b@example.com", "Membership" => "Full Time" },
      { "Name" => "C", "Email" => "c@example.com", "Membership" => "Part Time" },
    ]
    result = preview_for(rows, plan_mapping: { "Full Time" => 42 })

    memberships = result.preview[:membership_values]
    full_time = memberships.find { |m| m[:value] == "Full Time" }
    part_time = memberships.find { |m| m[:value] == "Part Time" }

    assert_equal 2, full_time[:count]
    assert full_time[:mapped]
    assert_equal 42, full_time[:mapped_plan_id]

    refute part_time[:mapped]
    # The unmapped membership produces a per-row warning.
    part_time_row = result.preview[:rows].find { |r| r[:membership] == "Part Time" }
    assert(part_time_row[:warnings].any? { |w| w.include?("not mapped") })
  end
end

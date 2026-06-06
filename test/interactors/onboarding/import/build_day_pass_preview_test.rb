require "test_helper"

class Onboarding::Import::BuildDayPassPreviewTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member = users(:cowork_tahoe_member) # tim@jellyswitch.com
    @dpt = day_pass_type(:cowork_tahoe_day_pass_type) # "Standard Day Pass"
    @cm = { email: "Email", day_pass_type: "Type", day: "Date", complimentary: "Comp" }
    @mapping = { "Standard Day Pass" => @dpt.id }
    ActsAsTenant.current_tenant = @operator
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def preview(rows, type_mapping: @mapping)
    Onboarding::Import::BuildDayPassPreview.call(
      location: @location, rows: rows, column_mapping: @cm, type_mapping: type_mapping,
    )
  end

  test "fails without a location" do
    assert Onboarding::Import::BuildDayPassPreview.call(location: nil, rows: []).failure?
  end

  test "resolves a user, maps the type, and parses the date" do
    rows = [{ "Email" => "tim@jellyswitch.com", "Type" => "Standard Day Pass", "Date" => "2024-03-01", "Comp" => "no" }]
    row = preview(rows).preview[:rows].first

    assert_equal @member.id, row[:user_id]
    assert_equal @dpt.id, row[:mapped_type_id]
    assert_equal "2024-03-01", row[:day]
    assert_nil row[:error]
    refute row[:complimentary]
  end

  test "errors when the user cannot be resolved" do
    rows = [{ "Email" => "nobody@example.com", "Type" => "Standard Day Pass", "Date" => "2024-03-01" }]
    assert_match(/user not found/, preview(rows).preview[:rows].first[:error])
  end

  test "errors when the day-pass type is not mapped" do
    rows = [{ "Email" => "tim@jellyswitch.com", "Type" => "Mystery Pass", "Date" => "2024-03-01" }]
    assert_match(/not mapped/, preview(rows).preview[:rows].first[:error])
  end

  test "errors on an invalid date" do
    rows = [{ "Email" => "tim@jellyswitch.com", "Type" => "Standard Day Pass", "Date" => "nope" }]
    assert_match(/date/, preview(rows).preview[:rows].first[:error])
  end

  test "detects an already-imported day pass" do
    DayPass.create!(user: @member, billable: @member, day_pass_type: @dpt, day: Date.new(2024, 3, 1),
                    operator_id: @operator.id, location_id: @location.id, imported: true)

    rows = [{ "Email" => "tim@jellyswitch.com", "Type" => "Standard Day Pass", "Date" => "2024-03-01" }]
    result = preview(rows)

    assert result.preview[:rows].first[:exists]
    assert_equal 1, result.preview[:summary][:existing]
  end
end

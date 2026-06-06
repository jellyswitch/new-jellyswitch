require "test_helper"

class OfficerndImportJobTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
  end

  def build_members_import(csv_body, column_mapping)
    import = nil
    ActsAsTenant.with_tenant(@operator) do
      import = @operator.officernd_imports.create!(
        kind: "members", location_id: @location.id, column_mapping: column_mapping,
      )
      import.csv.attach(io: StringIO.new(csv_body), filename: "members.csv", content_type: "text/csv")
      import.update!(headers: import.parsed.headers, row_count: import.parsed.row_count)
    end
    import
  end

  test "runs a members import and marks it committed" do
    import = build_members_import(
      "Name,Email\nNew Person,newperson@example.com\n",
      { "email" => "Email", "name" => "Name" },
    )

    assert_difference -> { @operator.users.where("lower(email) = ?", "newperson@example.com").count }, 1 do
      OfficerndImportJob.perform_now(import.id)
    end

    import.reload
    assert_equal "committed", import.status
    assert_equal 1, import.result_log.dig("summary", "users_created")
  end

  test "marks the import failed (not raising to the row level) when interactor fails" do
    import = build_members_import("Name,Email\nX,x@example.com\n", { "email" => "Email", "name" => "Name" })

    # Force the interactor to fail.
    Onboarding::Import::Commit.stubs(:call).returns(OpenStruct.new(success?: false, message: "boom"))

    OfficerndImportJob.perform_now(import.id)

    import.reload
    assert_equal "failed", import.status
    assert_equal "boom", import.result_log["error"]
  end

  test "does nothing for an unknown import id" do
    assert_nothing_raised { OfficerndImportJob.perform_now(-1) }
  end
end

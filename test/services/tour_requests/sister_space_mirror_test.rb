require 'test_helper'

class TourRequests::SisterSpaceMirrorTest < ActiveSupport::TestCase
  setup do
    setup_initial_user_fixtures
    @cowork_tahoe = operators(:cowork_tahoe)
    @ct_location  = locations(:cowork_tahoe_location)

    @untethered = Operator.create!(name: "Untethered", subdomain: "untethered", tour_widget_enabled: true)
    ActsAsTenant.with_tenant(@untethered) do
      @zephyr = @untethered.locations.create!(name: "Untethered - Lake Tahoe, NV", city: "Zephyr Cove", visible: true)
      @fulton = @untethered.locations.create!(name: "Untethered - Fulton, MO", city: "Fulton", visible: true)
    end
    @requester = User.create!(
      email: "tahoe+prospect@example.com", name: "Tahoe Prospect", phone: "555-0100", operator: @untethered,
      original_location_id: @zephyr.id, admin_created: true, password: "tempPass1!",
    )
  end

  def log_request(location, payload = { "message" => "Hot desk?", "preferred_time" => "Mornings", "source" => "widget" })
    ActsAsTenant.with_tenant(@untethered) do
      Activity.create!(
        user: @requester, operator: @untethered, kind: "tour_request",
        occurred_at: Time.current, subject: location, payload: payload,
      )
    end
  end

  test "Zephyr Cove request creates a Person + tour_request Activity at Cowork Tahoe" do
    source = log_request(@zephyr)

    mirror = nil
    assert_difference -> { User.where(operator: @cowork_tahoe).count } => 1 do
      mirror = TourRequests::SisterSpaceMirror.call(source)
    end

    assert mirror
    assert_equal @cowork_tahoe.id, mirror.operator_id
    assert_equal "tour_request", mirror.kind
    assert_equal @ct_location, mirror.subject
    assert_equal "Hot desk?", mirror.payload["message"]
    assert_equal "Mornings", mirror.payload["preferred_time"]
    assert_equal "untethered", mirror.payload.dig("mirrored_from", "operator_subdomain")
    assert_equal source.id, mirror.payload.dig("mirrored_from", "activity_id")
    assert_equal @zephyr.name, mirror.payload.dig("mirrored_from", "location_name")

    person = mirror.user
    assert_equal @cowork_tahoe.id, person.operator_id
    assert_equal @requester.email, person.email
    assert_equal "Tahoe Prospect", person.name
    assert_equal "555-0100", person.phone
    assert_equal @ct_location.id, person.original_location_id
    assert person.admin_created

    source.reload
    assert_equal "tml", source.payload.dig("mirrored_to", "operator_subdomain")
    assert_equal "Cowork Tahoe", source.payload.dig("mirrored_to", "operator_name")
    assert_equal @ct_location.name, source.payload.dig("mirrored_to", "location_name")
    assert_equal person.id, source.payload.dig("mirrored_to", "user_id")
    assert_equal mirror.id, source.payload.dig("mirrored_to", "activity_id")
    # Existing fields survive the merge.
    assert_equal "Hot desk?", source.payload["message"]
  end

  test "reuses an existing Cowork Tahoe Person with the same email" do
    existing = User.create!(
      email: @requester.email, name: "Already Here", operator: @cowork_tahoe,
      original_location_id: @ct_location.id, admin_created: true, password: "tempPass1!",
    )
    source = log_request(@zephyr)

    assert_no_difference -> { User.count } do
      mirror = TourRequests::SisterSpaceMirror.call(source)
      assert_equal existing.id, mirror.user_id
    end
    assert_equal "Already Here", existing.reload.name
  end

  test "Fulton, MO requests do not mirror" do
    source = log_request(@fulton)

    assert_no_difference -> { User.count }, -> { Activity.where(kind: "tour_request").count } do
      assert_nil TourRequests::SisterSpaceMirror.call(source)
    end
    assert_nil source.reload.payload["mirrored_to"]
  end

  test "requests without a location do not mirror" do
    source = log_request(nil)
    assert_nil TourRequests::SisterSpaceMirror.call(source)
  end

  test "other operators' tour requests do not mirror" do
    ct_requester = User.create!(
      email: "ct+prospect@example.com", name: "CT Prospect", operator: @cowork_tahoe,
      original_location_id: @ct_location.id, admin_created: true, password: "tempPass1!",
    )
    @ct_location.update!(city: "Zephyr Cove")
    source = ActsAsTenant.with_tenant(@cowork_tahoe) do
      Activity.create!(user: ct_requester, operator: @cowork_tahoe, kind: "tour_request",
                       occurred_at: Time.current, subject: @ct_location, payload: {})
    end

    assert_no_difference -> { Activity.count } do
      assert_nil TourRequests::SisterSpaceMirror.call(source)
    end
  end

  test "a mirror failure is swallowed and leaves the source untouched" do
    source = log_request(@zephyr)
    User.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid)

    assert_no_difference -> { Activity.count } do
      assert_nil TourRequests::SisterSpaceMirror.call(source)
    end
    assert_nil source.reload.payload["mirrored_to"]
  end
end

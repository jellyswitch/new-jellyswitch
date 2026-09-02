require "test_helper"

# Task 13 (ADR 0026): the operator Day Pass Type form's kind select + Day
# Office room pool editor. Request-level only, per house convention for this
# controller (see day_pass_types_daily_limit_test.rb) — the Stimulus
# show/hide and blank-allowance-to-zero behavior is client-side and out of
# reach here; see day_pass_type_form_controller.js.
class Operator::DayPassTypesControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    log_in users(:cowork_tahoe_admin)
  end

  test "creates a day_office type with an ordered room pool" do
    room_a = Room.create!(name: "Office A", operator: @operator, location: @location)
    room_b = Room.create!(name: "Office B", operator: @operator, location: @location)

    post day_pass_types_path,
         params: {
           day_pass_type: { name: "Executive Office", amount_in_cents: "150", kind: "day_office" },
           office_room_positions: { room_a.id => "2", room_b.id => "1" },
         },
         env: default_env

    created = DayPassType.order(:id).last
    assert_equal "Executive Office", created.name
    assert_equal "day_office", created.kind
    assert_equal @location, created.location
    assert_equal 0, created.included_meeting_room_minutes,
                 "day_office with no allowance submitted must default to 0 (overage from minute one)"
    assert_equal [room_b.id, room_a.id], created.office_rooms.map(&:id),
                 "pool order must follow the submitted positions, not submission order"
  end

  test "a bounced create keeps the operator's typed pool positions (sticky inputs)" do
    room_a = Room.create!(name: "Office A", operator: @operator, location: @location)
    room_b = Room.create!(name: "Office B", operator: @operator, location: @location)

    post day_pass_types_path,
         params: {
           day_pass_type: {
             name: "Executive Office", amount_in_cents: "150", kind: "day_office",
             # cowork_tahoe_location is in CA, where expiration is restricted
             # (expiration_allowed_for_location) — a real, unstubbed validation
             # failure, so :new genuinely re-renders instead of saving.
             expires_after_days: "30",
           },
           office_room_positions: { room_a.id => "2", room_b.id => "1" },
         },
         env: default_env

    assert_response :unprocessable_entity
    assert_nil DayPassType.find_by(name: "Executive Office")

    body = Nokogiri::HTML(response.body)
    assert_equal "2", body.at_css("#office_room_positions_#{room_a.id}")["value"],
                 "the operator's typed position for room_a must survive the bounced save"
    assert_equal "1", body.at_css("#office_room_positions_#{room_b.id}")["value"],
                 "the operator's typed position for room_b must survive the bounced save"
  end

  test "update applies full-list room pool semantics: repositions and removes in one save" do
    type = DayPassType.create!(name: "Office", operator: @operator, location: @location,
                               amount_in_cents: 100, kind: "day_office", included_meeting_room_minutes: 0)
    room_a = Room.create!(name: "Office A", operator: @operator, location: @location)
    room_b = Room.create!(name: "Office B", operator: @operator, location: @location)
    room_c = Room.create!(name: "Office C", operator: @operator, location: @location)
    type.assign_office_rooms!(room_a.id => 1, room_b.id => 2)

    patch day_pass_type_path(type),
          params: {
            day_pass_type: { name: type.name, kind: "day_office" },
            office_room_positions: { room_a.id => "2", room_c.id => "1" },
          },
          env: default_env

    assert_equal [room_c.id, room_a.id], type.reload.office_rooms.map(&:id),
                 "room_b was omitted from the submission and must be removed; room_a repositioned; room_c added"
  end

  test "showcase bullets: the edit form prefills the automatic lines and saving them untouched keeps automatic" do
    type = DayPassType.create!(name: "5 Pack", quantity: 5, operator: @operator, location: @location,
                               amount_in_cents: 16_000, included_meeting_room_minutes: 60)
    defaults = "5 day passes\n60 min meeting room time per day\nBuilding access during open hours"

    get edit_day_pass_type_path(type), env: default_env
    assert_response :success
    assert_includes response.body, "60 min meeting room time per day"

    patch day_pass_type_path(type),
          params: { day_pass_type: { name: type.name, features_text: defaults, features_default: defaults } },
          env: default_env
    assert_equal [], type.reload.features, "unedited automatic lines must not be frozen as operator lines"

    patch day_pass_type_path(type),
          params: { day_pass_type: { name: type.name, features_text: "5 day passes\nFree coffee", features_default: defaults } },
          env: default_env
    assert_equal ["5 day passes", "Free coffee"], type.reload.features, "edited lines replace the automatic ones"

    patch day_pass_type_path(type),
          params: { day_pass_type: { name: type.name, features_text: "", features_default: "5 day passes\nFree coffee" } },
          env: default_env
    assert_equal [], type.reload.features, "clearing the box returns the product to automatic"
  end

  test "a pool-only failure keeps the type saved and sets a specific flash, without a 500" do
    type = DayPassType.create!(name: "Office", operator: @operator, location: @location,
                               amount_in_cents: 100, kind: "day_office", included_meeting_room_minutes: 0)
    other_location = Location.create!(operator: @operator, name: "Other Location")
    stray = Room.create!(name: "Stray", operator: @operator, location: other_location)

    patch day_pass_type_path(type),
          params: {
            day_pass_type: { name: "Renamed Office", kind: "day_office" },
            office_room_positions: { stray.id => "1" },
          },
          env: default_env

    assert_response :redirect, "the type itself saved fine; this must not surface as a 500 or a re-render"
    assert_equal "Renamed Office", type.reload.name, "the name change must not be rolled back by the pool failure"
    assert_empty type.day_pass_type_rooms, "the invalid cross-location row must not be persisted"
    # Note: under a real request, acts_as_scopable's current-location scoping
    # (set by Operator::BaseController#set_resource_scopes) hides the
    # cross-location room from the belongs_to :room lookup entirely, so
    # Rails' own presence validation ("Room must exist") fires instead of
    # DayPassTypeRoom#room_matches_type_location's custom message — unlike
    # the unscoped model-level test in day_pass_type_test.rb, which sees the
    # room and gets the custom message. Both are ActiveRecord::RecordInvalid;
    # this test only pins the flash template, not which of the two messages.
    assert_match(/\ARenamed Office was saved, but the room pool couldn't be updated: /, flash[:error])
    assert_match(/Room must exist/, flash[:error])
  end

  test "switching kind from day_office to standard clears the pool" do
    type = DayPassType.create!(name: "Office", operator: @operator, location: @location,
                               amount_in_cents: 100, kind: "day_office", included_meeting_room_minutes: 0)
    room = Room.create!(name: "Office A", operator: @operator, location: @location)
    type.assign_office_rooms!(room.id => 1)
    assert type.day_pass_type_rooms.exists?

    patch day_pass_type_path(type),
          params: { day_pass_type: { name: type.name, kind: "standard" } },
          env: default_env

    assert_equal "standard", type.reload.kind
    assert_empty type.day_pass_type_rooms, "an orphaned pool must not survive a switch back to standard"
  end

  # location is auto-set from current_location on every create in this
  # controller, and current_location can never be blank while a logged-in
  # admin reaches #create (Operator::BaseController#reset_location logs them
  # out first) — so a day_office-without-location create can't be produced
  # through real form params. Stubbing day_pass_type_params is the narrowest
  # way to exercise the same failure branch the controller already has for
  # any interactor failure, and it doubles as a regression check that the
  # new pool markup doesn't 500 when rendering :new for an in-memory
  # day_office record with no location (the pool section reads
  # current_location for the new form, not day_pass_type.location, for
  # exactly this reason).
  test "a day_office save that ends up without a location re-renders :new with the validation error" do
    Operator::DayPassTypesController.any_instance.stubs(:day_pass_type_params).returns(
      { name: "No Location Office", amount_in_cents: 10_000, kind: "day_office" }
    )

    post day_pass_types_path,
         params: { day_pass_type: { name: "No Location Office", amount_in_cents: "100", kind: "day_office" } },
         env: default_env

    assert_response :unprocessable_entity
    assert_match(/is required for Day Office types/, response.body)
    assert_nil DayPassType.find_by(name: "No Location Office")
  end

  test "update permits :kind but not arbitrary/protected fields" do
    type = day_pass_type(:cowork_tahoe_day_pass_type)
    assert_equal "standard", type.kind
    other_operator_id = operators(:cowork_tahoe).id + 999
    other_location = Location.create!(operator: @operator, name: "Other Location")

    patch day_pass_type_path(type),
          params: {
            day_pass_type: {
              name: type.name,
              kind: "day_office",
              operator_id: other_operator_id,
              location_id: other_location.id,
            },
          },
          env: default_env

    type.reload
    assert_equal "day_office", type.kind, ":kind must be permitted"
    assert_equal @operator.id, type.operator_id, "operator_id must not be mass-assignable"
    assert_equal @location, type.location, "location_id must not be mass-assignable via update"
  end

  test "edit form warns when the location's posted hours can't host a day office" do
    @location.update!(working_day_start: "22:00", working_day_end: "05:00")
    type = DayPassType.create!(name: "Office", operator: @operator, location: @location,
                               amount_in_cents: 100, kind: "day_office", included_meeting_room_minutes: 0)

    get edit_day_pass_type_path(type), env: default_env

    assert_response :success
    assert_match(/posted hours are blank or overnight/, response.body)
  end
end

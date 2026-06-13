require "test_helper"
require "ostruct"

# Coverage for `ApplicationHelper#brand_color`, which drives the dashboard's
# `--brand-color` CSS var (buttons, links, active tabs). Legacy operators are
# pinned to hand-tuned colors by subdomain; every other operator — i.e. every
# self-serve brand created through onboarding — now derives its color from the
# `primary_color` field it sets during the Branding step. Before this change
# unlisted subdomains fell back to Bootstrap blue regardless of their brand.
class ApplicationHelperTest < ActionView::TestCase
  include ApplicationHelper

  def op(subdomain:, primary_color: nil)
    OpenStruct.new(subdomain: subdomain, primary_color: primary_color)
  end

  test "legacy subdomains keep their pinned colors regardless of primary_color" do
    assert_equal "#76B82A", brand_color(op(subdomain: "tml", primary_color: "#000000"))
    assert_equal "#1B3A4B", brand_color(op(subdomain: "untethered"))
  end

  test "self-serve brand uses its primary_color" do
    assert_equal "#4B3619", brand_color(op(subdomain: "tahoelonghouse", primary_color: "#4B3619"))
  end

  test "normalizes a primary_color stored without a leading hash" do
    assert_equal "#4B3619", brand_color(op(subdomain: "tahoelonghouse", primary_color: "4B3619"))
  end

  test "falls back to Bootstrap blue when no primary_color is set" do
    assert_equal "#007bff", brand_color(op(subdomain: "newbrand", primary_color: nil))
    assert_equal "#007bff", brand_color(op(subdomain: "newbrand", primary_color: ""))
  end

  test "brand_color_hover darkens a self-serve primary_color without erroring" do
    hover = brand_color_hover(op(subdomain: "tahoelonghouse", primary_color: "#4B3619"))
    assert_match(/\A#[0-9a-f]{6}\z/, hover)
    refute_equal "#4B3619", hover
  end

  # ---- active_working_hours? -------------------------------------------------
  # The operator dashboard renders an "open now?" indicator from the location's
  # working hours via the strict `working_hours` gem. Legacy/un-padded data like
  # "5:00" used to raise WorkingHours::InvalidConfiguration and 500 the page; the
  # helper must degrade to "closed" instead of crashing.

  # A bare location double answering the open-day predicates the working-hours
  # config reads (open_sunday? .. open_saturday?) plus the two time strings.
  class WorkingHoursDouble
    def initialize(start:, ending:, open: true)
      @start = start
      @ending = ending
      @open = open
    end

    def working_day_start = @start
    def working_day_end = @ending

    %i[open_sunday open_monday open_tuesday open_wednesday open_thursday open_friday open_saturday].each do |day|
      define_method("#{day}?") { @open }
    end
  end

  test "active_working_hours? returns false instead of raising on un-padded legacy times" do
    loc = WorkingHoursDouble.new(start: "5:00", ending: "18:00", open: true)
    assert_nothing_raised { active_working_hours?(loc) }
    assert_equal false, active_working_hours?(loc)
  end

  test "active_working_hours? is true inside an all-day open window" do
    loc = WorkingHoursDouble.new(start: "00:00", ending: "24:00", open: true)
    assert_equal true, active_working_hours?(loc)
  end

  test "active_working_hours? returns false when no days are open" do
    loc = WorkingHoursDouble.new(start: "09:00", ending: "17:00", open: false)
    assert_equal false, active_working_hours?(loc)
  end
end

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
end

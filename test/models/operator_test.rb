require 'test_helper'

class OperatorTest < ActiveSupport::TestCase
  test "tour_widget_active? requires enabled flag and at least one visible location" do
    operator = operators(:cowork_tahoe)

    operator.update!(tour_widget_enabled: false)
    refute operator.tour_widget_active?

    operator.update!(tour_widget_enabled: true)
    assert operator.tour_widget_active?, "should be active with enabled + visible location"

    # If the operator has no visible locations, widget should be inactive.
    operator.locations.update_all(visible: false)
    refute operator.reload.tour_widget_active?
  end

  test "tour_widget_thank_you_url rejects non-http schemes" do
    operator = operators(:cowork_tahoe)
    operator.tour_widget_thank_you_url = "javascript:alert(1)"
    refute operator.valid?
    assert_includes operator.errors[:tour_widget_thank_you_url].first, "http"
  end

  test "tour_widget_thank_you_url accepts https" do
    operator = operators(:cowork_tahoe)
    operator.tour_widget_thank_you_url = "https://example.com/thanks"
    assert operator.valid?
  end
end

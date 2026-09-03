require 'test_helper'

class Operator::SettingsTourWidgetTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @admin = users(:cowork_tahoe_admin)
    log_in @admin
  end

  test "GET tour_widget lands on the Website Widgets picker with the tour panel open" do
    get settings_tour_widget_path, env: default_env
    assert_redirected_to settings_website_widgets_path(widget: "tour")
    get settings_website_widgets_path(widget: "tour"), env: default_env
    assert_response :success
    assert_select "h2", /Website Widgets/i
    assert_select "#widget-picker a.nav-link.active[data-widget=tour]", text: /Tour Request/
    assert_select "#widget-tour.tab-pane.active input[name='operator[tour_widget_enabled]']"
  end

  test "tour_widget_enabled toggle: label[for] matches checkbox id (custom-switch clickability)" do
    get settings_website_widgets_path(widget: "tour"), env: default_env
    assert_response :success
    # Bootstrap 4 custom-switch visually hides the input; only the label is clickable.
    # If label[for] doesn't match the checkbox id, clicking the toggle does nothing.
    checkbox_id = css_select("input[type=checkbox][name='operator[tour_widget_enabled]']").first&.attr("id")
    label_for   = css_select("label.custom-control-label[for='#{checkbox_id}']").first&.attr("for")
    assert_equal checkbox_id, label_for,
      "tour_widget_enabled label[for] must match its checkbox id, otherwise the custom-switch toggle is unclickable"
  end

  test "GET tour_widget redirects when current user is not admin" do
    reset!
    log_in users(:cowork_tahoe_member)
    get settings_tour_widget_path, env: default_env
    assert_response :redirect
  end

  test "PATCH update_tour_widget persists settings" do
    patch settings_update_tour_widget_path, env: default_env, params: {
      operator: {
        tour_widget_enabled: "1",
        tour_widget_thank_you_url: "https://example.com/thanks",
      }
    }
    assert_redirected_to settings_website_widgets_path(widget: "tour")
    operator = @admin.operator.reload
    assert operator.tour_widget_enabled
    assert_equal "https://example.com/thanks", operator.tour_widget_thank_you_url
  end

  test "PATCH update_tour_widget rejects javascript: URLs" do
    patch settings_update_tour_widget_path, env: default_env, params: {
      operator: { tour_widget_thank_you_url: "javascript:alert(1)" }
    }
    assert_response :unprocessable_entity
    # Re-rendered on the picker with the tour panel still open.
    assert_select "#widget-picker a.nav-link.active[data-widget=tour]"
  end
end

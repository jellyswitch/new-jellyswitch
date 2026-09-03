require 'test_helper'

class Operator::SettingsWebsiteWidgetsTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @admin = users(:cowork_tahoe_admin)
    log_in @admin
  end

  test "renders the shared look & feel form and a picker with all four widgets" do
    get settings_website_widgets_path, env: default_env
    assert_response :success
    assert_select "select[name='operator[embed_font]']"
    assert_select "input[name='operator[embed_accent_override]']"
    assert_select "input[name='operator[showcase_button_color]']"
    %w[concierge tour showcase offices].each do |key|
      assert_select "#widget-picker a.nav-link[data-widget=#{key}]"
      assert_select "#widget-#{key}.tab-pane"
    end
  end

  test "Concierge is the default panel and carries its own settings, snippet, and preview" do
    get settings_website_widgets_path, env: default_env
    assert_select "#widget-picker a.nav-link.active[data-widget=concierge]"
    assert_select "#widget-concierge.tab-pane.active input[name='operator[concierge_enabled]']"
    assert_select "#widget-concierge textarea#cx-launcher-snippet"
    assert_select "#widget-concierge iframe[title='Concierge preview']"
  end

  test "every widget panel carries a live preview" do
    get settings_website_widgets_path, env: default_env
    assert_select "#widget-concierge iframe[title='Concierge preview']"
    assert_select "#widget-tour iframe[title='Tour widget preview']"
    assert_select "#widget-showcase iframe[title='Showcase preview']"
    assert_select "#widget-offices iframe[title='Office Inventory preview']"
    # Script embeds preview through a signed token so they show even while disabled.
    assert_match %r{/embed/showcase/#{@admin.operator.subdomain}\?preview_token=}, response.body
    assert_match %r{/embed/office_inventory/#{@admin.operator.subdomain}\?preview_token=}, response.body
  end

  test "?widget= picks the open panel" do
    get settings_website_widgets_path(widget: "showcase"), env: default_env
    assert_select "#widget-picker a.nav-link.active[data-widget=showcase]"
    assert_select "#widget-showcase.tab-pane.active input[name='operator[showcase_enabled]']"
    assert_select "#widget-concierge.tab-pane.active", count: 0

    get settings_website_widgets_path(widget: "offices"), env: default_env
    assert_select "#widget-offices.tab-pane.active input[name='operator[office_inventory_enabled]']"
  end

  test "an unknown ?widget= falls back to the first panel" do
    get settings_website_widgets_path(widget: "nope"), env: default_env
    assert_response :success
    assert_select "#widget-picker a.nav-link.active[data-widget=concierge]"
  end

  test "GET concierge redirects into the picker" do
    get settings_concierge_path, env: default_env
    assert_redirected_to settings_website_widgets_path(widget: "concierge")
  end

  test "saving look & feel returns to the widget that was open" do
    patch settings_update_website_widgets_path, env: default_env,
          params: { widget: "offices", operator: { embed_font: "Georgia, serif", office_inventory_enabled: "1" } }
    assert_redirected_to settings_website_widgets_path(widget: "offices")
    operator = @admin.operator.reload
    assert_equal "Georgia, serif", operator.embed_font
    assert operator.office_inventory_enabled
  end

  test "a bad hex color re-renders the picker on the same widget" do
    patch settings_update_website_widgets_path, env: default_env,
          params: { widget: "showcase", operator: { showcase_button_color: "not-a-color" } }
    assert_response :unprocessable_entity
    assert_select "#widget-picker a.nav-link.active[data-widget=showcase]"
  end

  test "saving concierge settings returns to the concierge panel" do
    patch settings_update_concierge_path, env: default_env,
          params: { operator: { concierge_assistant_name: "Lab Bot" } }
    assert_redirected_to settings_website_widgets_path(widget: "concierge")
    assert_equal "Lab Bot", @admin.operator.reload.concierge_assistant_name
  end
end

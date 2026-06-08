# == Schema Information
#
# Table name: operators
#
#  id                                  :bigint(8)        not null, primary key
#  android_server_key                  :string
#  android_url                         :string
#  announcements_enabled               :boolean          default(TRUE), not null
#  approval_required                   :boolean          default(TRUE), not null
#  billing_state                       :string           default("demo"), not null
#  building_address                    :string           default("not set"), not null
#  bulletin_board_enabled              :boolean          default(FALSE), not null
#  cancellation_window_hours           :integer          default(24), not null
#  checkin_notifications               :boolean          default(TRUE), not null
#  checkin_required                    :boolean          default(FALSE), not null
#  childcare_enabled                   :boolean          default(FALSE), not null
#  contact_email                       :string
#  contact_name                        :string
#  contact_phone                       :string
#  credits_enabled                     :boolean          default(FALSE), not null
#  crm_enabled                         :boolean          default(FALSE), not null
#  day_pass_cost_in_cents              :integer          default(2500), not null
#  day_pass_notifications              :boolean          default(TRUE), not null
#  door_integration_enabled            :boolean          default(TRUE), not null
#  email_enabled                       :boolean          default(FALSE), not null
#  events_enabled                      :boolean          default(TRUE), not null
#  google_reviews_url                  :string
#  ios_url                             :string
#  kisi_api_key                        :string
#  last_activities_backfilled_at       :datetime
#  mailchimp_api_key                   :string
#  member_feedback_notifications       :boolean          default(TRUE), not null
#  membership_notifications            :boolean          default(TRUE), not null
#  membership_text                     :string
#  name                                :string           not null
#  offices_enabled                     :boolean          default(TRUE), not null
#  paid_room_reservation_notifications :boolean          default(TRUE), not null
#  post_notifications                  :boolean          default(TRUE), not null
#  refund_fee_percent                  :integer          default(0), not null
#  refund_notifications                :boolean          default(TRUE), not null
#  renewal_reminder_days               :integer          default(7)
#  reservation_notifications           :boolean          default(FALSE), not null
#  rooms_enabled                       :boolean          default(TRUE), not null
#  sender_email                        :string
#  signup_notifications                :boolean          default(FALSE), not null
#  skip_onboarding                     :boolean          default(FALSE), not null
#  snippet                             :string           default("Generic snippet about the space"), not null
#  square_footage                      :integer          default(0), not null
#  stripe_access_token                 :string
#  stripe_publishable_key              :string
#  stripe_refresh_token                :string
#  subdomain                           :string           not null
#  tour_widget_enabled                 :boolean          default(FALSE), not null
#  tour_widget_thank_you_url           :string
#  wifi_name                           :string           default("not set"), not null
#  wifi_password                       :string           default("not set"), not null
#  created_at                          :datetime         not null
#  updated_at                          :datetime         not null
#  bundle_id                           :string
#  firebase_project_id                 :string
#  mailchimp_audience_id               :string
#  stripe_user_id                      :string
#
# Indexes
#
#  index_operators_on_subdomain  (subdomain) UNIQUE
#
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

  test "accepts valid hex brand colors" do
    op = operators(:cowork_tahoe)
    op.primary_color = "#436541"
    op.accent_color = "#C9A23A"
    assert op.valid?, op.errors.full_messages.to_sentence
  end

  test "rejects malformed hex brand colors" do
    op = operators(:cowork_tahoe)
    op.primary_color = "not-a-color"
    refute op.valid?
    assert_includes op.errors[:primary_color], "is invalid"
  end

  test "allows blank brand colors (legacy operators)" do
    op = operators(:cowork_tahoe)
    op.primary_color = nil
    op.accent_color = ""
    assert op.valid?, op.errors.full_messages.to_sentence
  end

  test "subdomain rejects bad format, reserved words, and blank" do
    op = operators(:cowork_tahoe)
    op.subdomain = "Bad Sub"      # spaces + uppercase
    refute op.valid?
    op.subdomain = "-leadinghyphen"
    refute op.valid?
    op.subdomain = "app"          # reserved
    refute op.valid?
    op.subdomain = ""
    refute op.valid?
  end

  test "subdomain accepts a clean value" do
    op = operators(:cowork_tahoe)
    op.subdomain = "tahoelonghouse"
    assert op.valid?, op.errors.full_messages.to_sentence
  end

  test "app_icon_image can be attached" do
    op = operators(:cowork_tahoe)
    op.app_icon_image.attach(
      io: File.open(Rails.root.join("test/fixtures/files/app_icon.png")),
      filename: "app_icon.png", content_type: "image/png"
    )
    assert op.app_icon_image.attached?
  end
end

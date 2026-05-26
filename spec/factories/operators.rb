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
FactoryBot.define do
  factory :operator do
    sequence(:name) { |n| "Coworking Space #{n}" }
    sequence(:subdomain) { |n| "cowork#{n}" }
    snippet { "A great place to work and collaborate." }
    wifi_name { "Cowork WiFi" }
    wifi_password { "password123" }
    building_address { "123 Main St, Anytown, USA 12345" }
    approval_required { true }
    contact_name { "John Doe" }
    contact_email { "contact@example.com" }
    contact_phone { "555-123-4567" }
    day_pass_cost_in_cents { 2000 }
    square_footage { 5000 }
    email_enabled { false }
    billing_state { "production" }
    checkin_required { false }
    membership_text { "Flexible membership options available." }
    skip_onboarding { false }
    announcements_enabled { true }
    events_enabled { true }
    door_integration_enabled { true }
    rooms_enabled { true }
    offices_enabled { true }
    reservation_notifications { false }
    membership_notifications { true }
    signup_notifications { false }
    day_pass_notifications { true }
    member_feedback_notifications { true }
    checkin_notifications { true }
    refund_notifications { true }
    post_notifications { true }
    credits_enabled { false }
    childcare_enabled { false }
    bulletin_board_enabled { false }
    crm_enabled { false }
  end
end

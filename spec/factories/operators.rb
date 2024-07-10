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

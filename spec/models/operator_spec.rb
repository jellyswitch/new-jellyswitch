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
require 'rails_helper'

RSpec.describe Operator, type: :model do
  describe 'associations' do
    it { should have_many(:announcements) }
    it { should have_many(:day_passes) }
    it { should have_many(:day_pass_types) }
    it { should have_many(:doors) }
    it { should have_many(:door_punches) }
    it { should have_many(:feed_items) }
    it { should have_many(:invoices) }
    it { should have_many(:leads) }
    it { should have_many(:member_feedbacks) }
    it { should have_many(:operator_surveys) }
    it { should have_many(:organizations) }
    it { should have_many(:plan_categories) }
    it { should have_many(:plans) }
    it { should have_many(:rooms) }
    it { should have_many(:users) }
    it { should have_many(:offices) }
    it { should have_many(:office_leases) }
    it { should have_many(:locations) }
    it { should have_many(:weekly_updates) }

    it { should have_many(:childcare_reservations).through(:locations) }
    it { should have_many(:child_profiles).through(:users) }
    it { should have_many(:events).through(:locations) }
    it { should have_many(:posts).through(:locations) }
    it { should have_many(:subscriptions).through(:plans) }
  end

  describe 'attachments' do
    it { should have_one_attached(:background_image) }
    it { should have_one_attached(:logo_image) }
    it { should have_one_attached(:terms_of_service) }
    it { should have_one_attached(:push_notification_certificate) }
    it { should have_one_attached(:android_push_notification_key) }
  end

  describe 'scopes' do
    let!(:production_operator) { create(:operator, billing_state: 'production') }
    let!(:demo_operator) { create(:operator, billing_state: 'demo') }

    describe '.production' do
      it 'returns operators with production billing state' do
        expect(Operator.production).to include(production_operator)
        expect(Operator.production).not_to include(demo_operator)
      end
    end

    describe '.demo' do
      it 'returns operators with demo billing state' do
        expect(Operator.demo).to include(demo_operator)
        expect(Operator.demo).not_to include(production_operator)
      end
    end
  end

  describe 'instance methods' do
    let(:operator) { create(:operator) }

    describe '#has_mobile_app_links?' do
      it 'returns true when both iOS and Android URLs are present' do
        operator.update(ios_url: 'https://ios.app', android_url: 'https://android.app')
        expect(operator.has_mobile_app_links?).to be true
      end

      it 'returns false when either URL is missing' do
        operator.update(ios_url: nil, android_url: 'https://android.app')
        expect(operator.has_mobile_app_links?).to be false
      end
    end

    describe '#has_contact_info?' do
      it 'returns true when all contact fields are present' do
        operator.update(
          contact_name: 'John',
          contact_email: 'john@example.com',
          contact_phone: '1234567890'
        )
        expect(operator.has_contact_info?).to be true
      end

      it 'returns false when any contact field is missing' do
        operator.update(
          contact_name: 'John',
          contact_email: nil,
          contact_phone: '1234567890'
        )
        expect(operator.has_contact_info?).to be false
      end
    end

    describe '#demo?' do
      it 'returns true for demo billing state' do
        operator.update(billing_state: 'demo')
        expect(operator.demo?).to be true
      end
    end

    describe '#production?' do
      it 'returns true for production billing state' do
        operator.update(billing_state: 'production')
        expect(operator.production?).to be true
      end

      it 'returns true for southlakecoworking subdomain' do
        operator.update(subdomain: 'southlakecoworking')
        expect(operator.production?).to be true
      end
    end

    describe '#reset_stripe_to_demo!' do
      it 'resets stripe-related attributes' do
        operator.reset_stripe_to_demo!
        expect(operator.stripe_user_id).to eq(ENV['STRIPE_ACCOUNT_ID'])
        expect(operator.stripe_publishable_key).to be_nil
        expect(operator.stripe_refresh_token).to be_nil
        expect(operator.stripe_access_token).to be_nil
        expect(operator.billing_state).to eq('demo')
      end
    end

    describe '#onboarded?' do
      before do
        create(:plan, operator: operator)
        create(:day_pass_type, operator: operator)
        create(:user, operator: operator, role: :unassigned)
        operator.update!(stripe_user_id: "acct_test")
      end

      it 'returns true when all requirements are met' do
        expect(operator.onboarded?).to be true
      end

      context "with all wizard steps complete except Stripe" do
        let(:incomplete_operator) do
          op = create(:operator, stripe_user_id: nil)
          create(:plan, operator: op)
          create(:day_pass_type, operator: op)
          create(:user, operator: op, role: :unassigned)
          op
        end

        it "is NOT onboarded (Stripe required)" do
          expect(incomplete_operator.onboarded?).to be false
        end

        it "IS onboarded once Stripe connects" do
          incomplete_operator.update!(stripe_user_id: "acct_test1234")
          expect(incomplete_operator.onboarded?).to be true
        end
      end
    end
  end

  describe 'callbacks' do
    describe 'after_save' do
      it 'updates kisi_api_key for locations' do
        operator = create(:operator, kisi_api_key: 'new_key')
        location = create(:location, operator: operator, kisi_api_key: nil)

        operator.save
        location.reload

        expect(location.kisi_api_key).to eq('new_key')
      end
    end
  end

  describe "#crm_enabled?" do
    it "always returns true regardless of the DB column" do
      operator = create(:operator, crm_enabled: false)
      expect(operator.crm_enabled?).to be true
    end
  end
end

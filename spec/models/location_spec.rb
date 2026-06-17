# == Schema Information
#
# Table name: locations
#
#  id                                  :bigint(8)        not null, primary key
#  allow_hourly                        :boolean          default(FALSE), not null
#  announcements_enabled               :boolean          default(TRUE), not null
#  billing_state                       :string
#  building_access_instructions        :string
#  building_address                    :string
#  bulletin_board_enabled              :boolean          default(FALSE), not null
#  childcare_enabled                   :boolean          default(TRUE), not null
#  childcare_reservation_cost_in_cents :integer          default(0), not null
#  city                                :string
#  common_square_footage               :integer          default(0), not null
#  contact_email                       :string
#  contact_name                        :string
#  contact_phone                       :string
#  credit_cost_in_cents                :integer          default(0), not null
#  credits_enabled                     :boolean          default(FALSE), not null
#  crm_enabled                         :boolean          default(TRUE), not null
#  door_integration_enabled            :boolean          default(TRUE), not null
#  events_enabled                      :boolean          default(TRUE), not null
#  flex_square_footage                 :integer          default(0), not null
#  google_reviews_url                  :string
#  hourly_rate_in_cents                :integer          default(0), not null
#  kisi_api_key                        :string
#  latitude                            :decimal(10, 7)
#  longitude                           :decimal(10, 7)
#  name                                :string
#  new_users_get_free_day_pass         :boolean          default(FALSE), not null
#  offices_enabled                     :boolean          default(FALSE), not null
#  open_friday                         :boolean          default(TRUE), not null
#  open_monday                         :boolean          default(TRUE), not null
#  open_saturday                       :boolean          default(FALSE), not null
#  open_sunday                         :boolean          default(FALSE), not null
#  open_thursday                       :boolean          default(TRUE), not null
#  open_tuesday                        :boolean          default(TRUE), not null
#  open_wednesday                      :boolean          default(TRUE), not null
#  past_member_grace_days              :integer          default(180), not null
#  renewal_reminder_days               :integer
#  rooms_enabled                       :boolean          default(TRUE), not null
#  sender_email                        :string
#  snippet                             :string
#  square_footage                      :integer
#  state                               :string
#  stripe_access_token                 :string
#  stripe_publishable_key              :string
#  stripe_refresh_token                :string
#  time_zone                           :string           default("Pacific Time (US & Canada)"), not null
#  visible                             :boolean          default(TRUE), not null
#  wifi_name                           :string
#  wifi_password                       :string
#  working_day_end                     :string           default("18:00"), not null
#  working_day_start                   :string           default("09:00"), not null
#  zip                                 :string
#  created_at                          :datetime         not null
#  updated_at                          :datetime         not null
#  operator_id                         :bigint(8)
#  space_host_id                       :bigint(8)
#  stripe_user_id                      :string
#
# Indexes
#
#  index_locations_on_operator_id     (operator_id)
#  index_locations_on_space_host_id   (space_host_id)
#  index_locations_on_state_and_city  (state,city)
#  index_locations_on_zip             (zip)
#
require 'rails_helper'

RSpec.describe Location, type: :model do
  describe 'associations' do
    it { should have_many(:checkins) }
    it { should have_many(:childcare_slots) }
    it { should have_many(:childcare_reservations).through(:childcare_slots) }
    it { should have_many(:doors) }
    it { should have_many(:events) }
    it { should have_many(:rooms) }
    it { should have_many(:offices) }
    it { should have_many(:office_leases) }
    it { should have_many(:posts) }
    it { should have_many(:feed_items) }
    it { should have_many(:member_feedbacks) }
    it { should have_many(:announcements) }
    it { should have_many(:day_passes) }
    it { should have_many(:day_pass_types) }
    it { should have_many(:organizations) }
    it { should have_many(:weekly_updates) }
    it { should have_many(:plans) }
    it { should have_many(:plan_categories) }
    it { should have_many(:invoices) }
    it { should have_many(:users).with_foreign_key('original_location_id') }
    it { should have_many(:current_users).with_foreign_key('current_location_id') }
    it { should have_many(:tracking_pixels) }
    it { should have_many(:location_managements) }
    it { should have_many(:managers).through(:location_managements) }
    it { should have_many(:user_payment_profiles).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:working_day_start) }
    it { should validate_presence_of(:working_day_end) }
  end

  describe 'working-time self-healing' do
    # Rows written before `normalizes` shipped (Tahoe Longhouse onboarded the
    # day before it did), or via any path that bypasses it, can hold an
    # un-normalized value like "5:00". That fails the format validation on
    # EVERY save, silently blocking UNRELATED settings forms (e.g. WiFi).
    it 'normalizes a legacy un-normalized working time so the record stays saveable' do
      loc = create(:location)
      # Raw SQL to plant the un-normalized value exactly as a pre-`normalizes`
      # row would hold it — update_columns/assignment would cast (normalize) it.
      loc.class.connection.update(
        "UPDATE locations SET working_day_start = '5:00' WHERE id = #{loc.id}"
      )
      loc.reload
      expect(loc.working_day_start).to eq('5:00') # legacy value loads un-normalized, as on prod

      loc.wifi_name = 'New Network' # unrelated change, like the WiFi & Pixels form
      expect(loc.save).to be true
      expect(loc.reload.working_day_start).to eq('05:00')
    end

    it 'still rejects genuinely invalid working times' do
      loc = build(:location, working_day_start: '9am')
      expect(loc).not_to be_valid
      expect(loc.errors[:working_day_start]).to include('is invalid')
    end
  end

  describe 'attachments' do
    it { should have_one_attached(:background_image) }
    it { should have_one_attached(:photo) }
  end

  describe 'scopes' do
    describe '.visible' do
      let!(:visible_location) { create(:location, visible: true) }
      let!(:invisible_location) { create(:location, visible: false) }

      it 'returns only visible locations' do
        expect(Location.visible).to include(visible_location)
        expect(Location.visible).not_to include(invisible_location)
      end
    end
  end

  describe 'instance methods' do
    let(:location) { create(:location) }

    describe '#has_photo?' do
      it 'returns true when background_image is attached' do
        location.background_image.attach(
          io: File.open(Rails.root.join('spec', 'fixtures', 'test.jpg')),
          filename: 'test_image.jpg'
        )
        expect(location.has_photo?).to be true
      end

      it 'returns false when background_image is not attached' do
        expect(location.has_photo?).to be false
      end
    end

    describe '#has_categories?' do
      it 'returns true when there are plan categories with available plans' do
        category = create(:plan_category, location: location)
        create(:plan, plan_type: 'individual', available: true, visible: true, plan_category: category, location: location)
        expect(location.has_categories?).to be true
      end

      it 'returns false when there are no plan categories with available plans' do
        expect(location.has_categories?).to be false
      end
    end

    describe '#has_contact_info?' do
      it 'returns true when all contact fields are present' do
        location.update(
          contact_name: 'John',
          contact_email: 'john@example.com',
          contact_phone: '1234567890'
        )
        expect(location.has_contact_info?).to be true
      end

      it 'returns false when any contact field is missing' do
        location.update(
          contact_name: 'John',
          contact_email: nil,
          contact_phone: '1234567890'
        )
        expect(location.has_contact_info?).to be false
      end
    end

    describe '#full_address' do
      it 'returns the complete address string' do
        location.update(
          building_address: '123 Main St',
          city: 'Springfield',
          state: 'IL',
          zip: '12345'
        )
        expect(location.full_address).to eq('123 Main St, Springfield IL 12345')
      end
    end

    describe '#day_passes_enabled?' do
      it 'returns true when day pass types exist' do
        create(:day_pass_type, location: location)
        expect(location.day_passes_enabled?).to be true
      end

      it 'returns false when no day pass types exist' do
        expect(location.day_passes_enabled?).to be false
      end
    end

    describe '#memberships_enabled?' do
      it 'returns true when available individual plans exist' do
        create(:plan, plan_type: 'individual', available: true, visible: true, location: location)
        expect(location.memberships_enabled?).to be true
      end

      it 'returns false when no available individual plans exist' do
        expect(location.memberships_enabled?).to be false
      end
    end

    describe '#onboarded?' do
      it 'returns true when all requirements are met' do
        create(:plan, location: location)
        create(:day_pass_type, location: location)
        create(:user, original_location: location, role: :unassigned)
        expect(location.onboarded?).to be true
      end

      it 'returns false when requirements are not met' do
        expect(location.onboarded?).to be false
      end
    end

    describe '#stripe_setup?' do
      it 'returns true when stripe_user_id is present' do
        location.update(stripe_user_id: 'stripe_123')
        expect(location.stripe_setup?).to be true
      end

      it 'returns false when stripe_user_id is not present' do
        location.update(stripe_user_id: nil)
        expect(location.stripe_setup?).to be false
      end
    end
  end

  describe "past_member_grace_days" do
    let(:operator) { create(:operator) }
    let(:location) { build(:location, operator: operator) }

    it "defaults to 180 (6 months)" do
      location.save!
      expect(location.reload.past_member_grace_days).to eq(180)
    end

    it "is valid at the 120-day lower bound" do
      location.past_member_grace_days = 120
      expect(location).to be_valid
    end

    it "is valid at the 365-day upper bound" do
      location.past_member_grace_days = 365
      expect(location).to be_valid
    end

    it "is invalid below 120 days" do
      location.past_member_grace_days = 119
      expect(location).not_to be_valid
      expect(location.errors[:past_member_grace_days]).to be_present
    end

    it "is invalid above 365 days" do
      location.past_member_grace_days = 366
      expect(location).not_to be_valid
      expect(location.errors[:past_member_grace_days]).to be_present
    end

    it "is invalid when nil" do
      location.past_member_grace_days = nil
      expect(location).not_to be_valid
    end
  end

  describe "#crm_enabled?" do
    it "always returns true regardless of the DB column" do
      location = create(:location, crm_enabled: false)
      expect(location.crm_enabled?).to be true
    end
  end

  describe "after_create_commit seed_email_templates" do
    let(:operator) { create(:operator) }

    it "seeds product email templates for a newly created location" do
      expect {
        create(:location, operator: operator)
      }.to change { ProductEmailTemplate.count }.by_at_least(1)
    end

    it "inherits a sibling location's customized body when creating a second location" do
      first = create(:location, operator: operator)
      sibling = ProductEmailTemplate.find_by(operator: operator, location: first,
                                              product_type: "day_pass", email_type: "onboarding")
      sibling.update!(body: "<p>Customized for #{operator.name}</p>")

      second = create(:location, operator: operator)
      new_template = ProductEmailTemplate.find_by(operator: operator, location: second,
                                                   product_type: "day_pass", email_type: "onboarding")
      expect(new_template.body.to_s).to include("Customized for #{operator.name}")
    end
  end
end

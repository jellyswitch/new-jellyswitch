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
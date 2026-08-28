# == Schema Information
#
# Table name: product_email_templates
#
#  id                   :bigint(8)        not null, primary key
#  email_type           :string           not null
#  enabled              :boolean          default(FALSE)
#  follow_up_delay_days :integer
#  product_type         :string           not null
#  subject              :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  location_id          :bigint(8)
#  operator_id          :bigint(8)        not null
#
# Indexes
#
#  idx_pet_operator_location_product_email       (operator_id,location_id,product_type,email_type) UNIQUE
#  index_product_email_templates_on_location_id  (location_id)
#  index_product_email_templates_on_operator_id  (operator_id)
#
# Foreign Keys
#
#  fk_rails_...  (location_id => locations.id)
#  fk_rails_...  (operator_id => operators.id)
#
require "rails_helper"

RSpec.describe ProductEmailTemplate, type: :model do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user) { create(:user, operator: operator, current_location: location) }

  describe "EMAIL_TYPES" do
    it "includes re_engagement and past_member_recovery" do
      expect(ProductEmailTemplate::EMAIL_TYPES).to include("re_engagement", "past_member_recovery")
    end

    it "includes replenishment (the bundle zero-balance email)" do
      expect(ProductEmailTemplate::EMAIL_TYPES).to include("replenishment")
    end
  end

  describe "day_pass_bundle product type" do
    it "is a valid product type" do
      expect(ProductEmailTemplate::PRODUCT_TYPES).to include("day_pass_bundle")
    end

    it "labels as 'Day Pass Bundle'" do
      tmpl = ProductEmailTemplate.new(product_type: "day_pass_bundle", email_type: "onboarding")
      expect(tmpl.product_label).to eq("Day Pass Bundle")
    end

    describe ".seed_defaults_for" do
      before { ProductEmailTemplate.seed_defaults_for(operator, location: location) }

      it "seeds onboarding, follow_up (review) and replenishment templates" do
        %w[onboarding follow_up replenishment].each do |etype|
          expect(
            ProductEmailTemplate.find_by(operator: operator, location: location,
                                         product_type: "day_pass_bundle", email_type: etype)
          ).to be_present, "expected a day_pass_bundle #{etype} template"
        end
      end

      it "does not seed a re_engagement template for bundles (buyers are customers, not leads)" do
        expect(
          ProductEmailTemplate.find_by(operator: operator, location: location,
                                       product_type: "day_pass_bundle", email_type: "re_engagement")
        ).to be_nil
      end
    end

    describe ".replace_merge_tags with a DayPassBundle sendable" do
      let(:pack_type) { create(:day_pass_type, operator: operator, location: location, name: "10-Pack", quantity: 10) }
      let(:bundle) do
        create(:day_pass_bundle, user: user, day_pass_type: pack_type, operator: operator,
                                 quantity_purchased: 10, passes_remaining: 7,
                                 expires_at: Time.zone.local(2026, 12, 31))
      end

      it "resolves bundle-specific tags and leaves {{date}} untouched" do
        body = "{{quantity}} passes, {{passes_remaining}} left, expires {{expires_at}} on {{date}}"
        result = ProductEmailTemplate.replace_merge_tags(
          body, user: user, operator: operator, location: location, sendable: bundle
        )
        expect(result).to include("10 passes")
        expect(result).to include("7 left")
        expect(result).to include("December 31, 2026")
        expect(result).to include("{{date}}") # bundle has no single day; tag stays literal
      end
    end
  end

  describe ".seed_defaults_for" do
    before { ProductEmailTemplate.seed_defaults_for(operator, location: location) }

    it "creates re_engagement templates for day_pass and reservation" do
      day_pass_re = ProductEmailTemplate.find_by(operator: operator, location: location,
                                                 product_type: "day_pass", email_type: "re_engagement")
      expect(day_pass_re).to be_present
      expect(day_pass_re.follow_up_delay_days).to eq(14)
      expect(day_pass_re.enabled).to be false

      reservation_re = ProductEmailTemplate.find_by(operator: operator, location: location,
                                                    product_type: "reservation", email_type: "re_engagement")
      expect(reservation_re).to be_present
      expect(reservation_re.follow_up_delay_days).to eq(14)
    end

    it "creates a past_member_recovery template for membership" do
      past_member = ProductEmailTemplate.find_by(operator: operator, location: location,
                                                  product_type: "membership", email_type: "past_member_recovery")
      expect(past_member).to be_present
      expect(past_member.follow_up_delay_days).to eq(30)
    end

    it "creates a re_engagement template for membership (the member re-engagement automation)" do
      t = ProductEmailTemplate.find_by(operator: operator, location: location,
                                       product_type: "membership", email_type: "re_engagement")
      expect(t).to be_present
      expect(t.follow_up_delay_days).to eq(30)
      expect(t.body).to be_present # so it can actually be enabled (disable_when_body_blank)
    end

    it "does not create re_engagement for office_lease or signup_nudge" do
      %w[office_lease signup_nudge].each do |product|
        expect(ProductEmailTemplate.find_by(operator: operator, location: location,
                                            product_type: product, email_type: "re_engagement")).to be_nil
      end
    end

    it "is idempotent (re-running does not duplicate rows)" do
      count_before = ProductEmailTemplate.count
      ProductEmailTemplate.seed_defaults_for(operator, location: location)
      expect(ProductEmailTemplate.count).to eq(count_before)
    end

    it "seeds brand-stripped body content for day_pass × onboarding" do
      template = ProductEmailTemplate.find_by(operator: operator, location: location,
                                              product_type: "day_pass", email_type: "onboarding")
      expect(template.body.to_s).to include("{{first_name}}")
      expect(template.body.to_s).to include("{{space_name}}")
      expect(template.body.to_s).not_to include("Cowork Tahoe")
    end

    it "seeds body content for re_engagement templates" do
      template = ProductEmailTemplate.find_by(operator: operator, location: location,
                                              product_type: "day_pass", email_type: "re_engagement")
      expect(template.body.to_s).to include("{{days_since_last_visit}}")
    end

    it "seeds body content for past_member_recovery" do
      template = ProductEmailTemplate.find_by(operator: operator, location: location,
                                              product_type: "membership", email_type: "past_member_recovery")
      expect(template.body.to_s).to include("{{plan_canceled_on}}")
    end

    it "does not clobber a customized body on re-seed" do
      template = ProductEmailTemplate.find_by(operator: operator, location: location,
                                              product_type: "day_pass", email_type: "onboarding")
      template.update!(body: "<p>Operator's custom copy</p>")
      ProductEmailTemplate.seed_defaults_for(operator, location: location)
      expect(template.reload.body.to_s).to include("Operator's custom copy")
    end
  end

  describe "#has_delay?" do
    it "is true for re_engagement and past_member_recovery" do
      expect(ProductEmailTemplate.new(email_type: "re_engagement").has_delay?).to be true
      expect(ProductEmailTemplate.new(email_type: "past_member_recovery").has_delay?).to be true
    end
  end

  describe "#available_merge_tags" do
    it "includes {{days_since_last_visit}} for re_engagement" do
      template = ProductEmailTemplate.new(operator: operator, location: location,
                                          product_type: "day_pass", email_type: "re_engagement")
      tag_names = template.available_merge_tags.map { |t| t[:tag] }
      expect(tag_names).to include("{{days_since_last_visit}}")
    end

    it "includes {{plan_canceled_on}} for past_member_recovery" do
      template = ProductEmailTemplate.new(operator: operator, location: location,
                                          product_type: "membership", email_type: "past_member_recovery")
      tag_names = template.available_merge_tags.map { |t| t[:tag] }
      expect(tag_names).to include("{{plan_canceled_on}}")
    end

    it "does not include either new tag on standard templates" do
      template = ProductEmailTemplate.new(operator: operator, location: location,
                                          product_type: "membership", email_type: "onboarding")
      tag_names = template.available_merge_tags.map { |t| t[:tag] }
      expect(tag_names).not_to include("{{days_since_last_visit}}", "{{plan_canceled_on}}")
    end
  end

  describe ".replace_merge_tags for the new tags" do
    it "replaces {{days_since_last_visit}} with days since the user's last visit Activity" do
      Activity.create!(user: user, operator: operator, kind: "checkin",
                       occurred_at: 21.days.ago, subject: user)
      result = ProductEmailTemplate.replace_merge_tags(
        "Hi, it's been {{days_since_last_visit}} days.",
        user: user, operator: operator, location: location)
      expect(result).to eq("Hi, it's been 21 days.")
    end

    it "renders empty {{days_since_last_visit}} when the user has no visit Activity" do
      result = ProductEmailTemplate.replace_merge_tags(
        "Last visit: {{days_since_last_visit}}",
        user: user, operator: operator, location: location)
      expect(result).to eq("Last visit: ")
    end

    it "replaces {{plan_canceled_on}} with a formatted date" do
      Activity.create!(user: user, operator: operator, kind: "subscription_ended",
                       occurred_at: Time.zone.local(2025, 11, 3), subject: user)
      result = ProductEmailTemplate.replace_merge_tags(
        "Plan ended {{plan_canceled_on}}",
        user: user, operator: operator, location: location)
      expect(result).to eq("Plan ended November 3, 2025")
    end
  end

  describe ".seed_template with sibling-location fallback" do
    let(:location_b) { create(:location, operator: operator) }

    it "copies a sibling location's customized body when present" do
      ProductEmailTemplate.seed_defaults_for(operator, location: location)
      sibling = ProductEmailTemplate.find_by(operator: operator, location: location,
                                              product_type: "day_pass", email_type: "onboarding")
      sibling.update!(body: "<p>Operator's hand-crafted day_pass onboarding copy</p>")

      ProductEmailTemplate.seed_defaults_for(operator, location: location_b)

      new_template = ProductEmailTemplate.find_by(operator: operator, location: location_b,
                                                   product_type: "day_pass", email_type: "onboarding")
      expect(new_template.body.to_s).to include("Operator's hand-crafted day_pass onboarding copy")
    end

    it "falls back to WelcomeDripSeed defaults when no sibling has content" do
      ProductEmailTemplate.seed_defaults_for(operator, location: location_b)
      new_template = ProductEmailTemplate.find_by(operator: operator, location: location_b,
                                                   product_type: "day_pass", email_type: "onboarding")
      expect(new_template.body.to_s).to include("{{first_name}}")
    end
  end

  describe "before_save disable_when_body_blank" do
    # Creating the location auto-seeds default templates (Location
    # after_create_commit :seed_email_templates), which collide with the
    # explicit day_pass/onboarding templates these examples build. Clear them
    # so each example controls its own row.
    before { ProductEmailTemplate.where(operator: operator, location: location).delete_all }

    it "forces enabled=false when saving with a blank body" do
      template = ProductEmailTemplate.new(operator: operator, location: location,
                                           product_type: "day_pass", email_type: "onboarding",
                                           subject: "Subject", enabled: true)
      template.save!
      expect(template.enabled).to be false
    end

    it "keeps enabled=true when body has content" do
      template = ProductEmailTemplate.create!(operator: operator, location: location,
                                                product_type: "day_pass", email_type: "onboarding",
                                                subject: "Subject", body: "<p>Hello</p>", enabled: true)
      expect(template.enabled).to be true
    end

    it "flips a previously-enabled row to disabled when admin clears the body" do
      template = ProductEmailTemplate.create!(operator: operator, location: location,
                                                product_type: "day_pass", email_type: "onboarding",
                                                subject: "Subject", body: "<p>Hello</p>", enabled: true)
      template.update!(body: "")
      expect(template.reload.enabled).to be false
    end
  end
end

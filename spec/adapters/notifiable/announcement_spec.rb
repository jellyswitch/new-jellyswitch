require 'rails_helper'

RSpec.describe Notifiable::Announcement do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:announcement) { create(:announcement, operator: operator, location: location) }

  subject { described_class.new(announcement) }

  def active_member
    user = create(:user, operator: operator, original_location: location, current_location: location)
    plan = create(:plan, operator: operator, location: location, plan_type: "individual")
    create(:subscription, plan: plan, subscribable: user, billable: user, stripe_subscription_id: nil)
    user
  end

  describe "#recipients — marketing suppression is not an operational blackout" do
    it "still includes a suppressed ACTIVE member (e.g. a committed mover with months left)" do
      member = active_member
      member.update!(marketing_suppressed: true, marketing_suppressed_reason: "Churned: Moving away")

      expect(subject.send(:recipients)).to include(member)
    end

    it "still excludes a suppressed NON-patron" do
      lurker = create(:user, operator: operator, original_location: location, current_location: location)
      lurker.update!(marketing_suppressed: true, marketing_suppressed_reason: "Suppressed by admin")

      expect(subject.send(:recipients)).not_to include(lurker)
    end

    it "always excludes someone who opted out of email themselves" do
      member = active_member
      member.update!(email_opted_out: true)

      expect(subject.send(:recipients)).not_to include(member)
    end

    it "includes an ordinary active member" do
      member = active_member
      expect(subject.send(:recipients)).to include(member)
    end
  end
end
